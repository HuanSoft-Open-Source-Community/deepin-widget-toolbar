// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetpackage.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QTemporaryDir>

static const char kManifestFile[] = "manifest.json";

WidgetPackage::InstallResult WidgetPackage::install(
    const QString &packagePath, const QString &destWidgetsDir,
    const std::function<bool(const QString &widgetId)> &existsCheck)
{
    InstallResult result;
    const QFileInfo pkg(packagePath);
    if (!pkg.exists() || !pkg.isFile()) {
        qWarning() << "installFromFile: invalid package path" << packagePath;
        return result;
    }

    QTemporaryDir tmp;
    if (!tmp.isValid()) {
        qWarning() << "installFromFile: cannot create temp dir";
        return result;
    }

    // 1. 列出包内容，拒绝路径穿越（.. 或绝对路径）
    QProcess listProc;
    listProc.start("tar", {"-tJf", packagePath});
    if (!listProc.waitForFinished(15000) || listProc.exitCode() != 0) {
        qWarning() << "installFromFile: tar list failed" << listProc.readAllStandardError();
        return result;
    }
    const QStringList entries = QString::fromUtf8(listProc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const QString &e : entries) {
        if (e.startsWith('/') || e.contains("..")) {
            qWarning() << "installFromFile: unsafe path in package:" << e;
            return result;
        }
    }

    // 2. 解压到临时目录
    QProcess extractProc;
    extractProc.start("tar", {"-xJf", packagePath, "-C", tmp.path()});
    if (!extractProc.waitForFinished(30000) || extractProc.exitCode() != 0) {
        qWarning() << "installFromFile: tar extract failed" << extractProc.readAllStandardError();
        return result;
    }

    // 2.5 解压后校验：所有条目 canonical 路径必须位于临时目录内
    //（防包内 symlink/hardlink 前缀逃逸，如 CVE-2016-6321 一类）
    {
        const QString tmpCanonical = QDir(tmp.path()).canonicalPath();
        QDirIterator it(tmp.path(), QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString canonical = QFileInfo(it.next()).canonicalFilePath();
            if (canonical.isEmpty() || (!canonical.startsWith(tmpCanonical + "/") && canonical != tmpCanonical)) {
                qWarning() << "installFromFile: entry escapes temp dir:" << canonical;
                return result;
            }
        }
    }

    // 3. 在解压结果中查找 manifest.json（包根或第一层子目录）
    QString manifestPath;
    const QString rootManifest = tmp.path() + "/" + kManifestFile;
    if (QFile::exists(rootManifest)) {
        manifestPath = rootManifest;
    } else {
        const QDir root(tmp.path());
        const QStringList subDirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &sub : subDirs) {
            const QString candidate = tmp.path() + "/" + sub + "/" + kManifestFile;
            if (QFile::exists(candidate)) {
                manifestPath = candidate;
                break;
            }
        }
    }
    if (manifestPath.isEmpty()) {
        qWarning() << "installFromFile: manifest.json not found in package";
        return result;
    }

    // 4. 校验 manifest 中的 id 合法性
    QFile mf(manifestPath);
    if (!mf.open(QIODevice::ReadOnly)) {
        qWarning() << "installFromFile: cannot read manifest";
        return result;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(mf.readAll());
    const QJsonObject obj = doc.object();
    const QString widgetId = obj.value("id").toString();
    static const QRegularExpression idRe(QStringLiteral("^[A-Za-z0-9._-]+$"));
    if (!idRe.match(widgetId).hasMatch()) {
        qWarning() << "installFromFile: invalid widget id in manifest:" << widgetId;
        return result;
    }
    if (existsCheck && existsCheck(widgetId)) {
        qWarning() << "installFromFile: widget already exists:" << widgetId;
        return result;
    }

    // 5. 移动到安装目录
    const QFileInfo mfInfo(manifestPath);
    const QString sourceDir = mfInfo.absolutePath();
    const QString targetDir = destWidgetsDir + "/" + widgetId;
    QDir().mkpath(destWidgetsDir);
    QDir src(sourceDir);
    if (!src.rename(sourceDir, targetDir)) {
        qWarning() << "installFromFile: move to" << targetDir << "failed";
        return result;
    }

    result.ok = true;
    result.widgetId = widgetId;
    return result;
}

bool WidgetPackage::removeWidgetDir(const QString &widgetDir)
{
    QDir dir(widgetDir);
    if (!dir.removeRecursively()) {
        qWarning() << "uninstallWidget: failed to remove dir" << widgetDir;
        return false;
    }
    return true;
}
