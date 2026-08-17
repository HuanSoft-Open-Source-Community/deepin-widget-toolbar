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
#include <QUrl>

static const char kManifestFile[] = "manifest.json";
static const char kInstallTmpPrefix[] = ".install-";

// 递归复制目录树（rename 跨文件系统失败时的兜底路径）。
// QFile::copy 跟随 symlink 复制目标内容——逃逸校验已保证 symlink
// 不会指向临时目录之外，内部 symlink 落为普通文件副本反而更安全。
static bool copyDirRecursively(const QString &src, const QString &dst)
{
    QDir srcDir(src);
    if (!srcDir.exists())
        return false;
    if (!QDir().mkpath(dst))
        return false;

    QDirIterator it(src, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString entry = it.next();
        const QFileInfo info(entry);
        const QString relative = srcDir.relativeFilePath(entry);
        const QString target = dst + QLatin1Char('/') + relative;
        if (info.isDir()) {
            if (!QDir().mkpath(target))
                return false;
        } else if (!QFile::copy(entry, target)) {
            return false;
        }
    }
    return true;
}

WidgetPackage::InstallResult WidgetPackage::install(
    const QString &packagePath, const QString &destWidgetsDir,
    const std::function<bool(const QString &widgetId)> &existsCheck)
{
    InstallResult result;

    // 归一化输入：QML FileDialog.selectedFile 是 file:// URL（可能带百分号编码），
    // 必须先转成本地路径再交给 QFileInfo/tar，否则 exists() 恒为 false。
    QString localPath = packagePath;
    if (localPath.startsWith(QLatin1String("file://")))
        localPath = QUrl(packagePath).toLocalFile();

    const QFileInfo pkg(localPath);
    if (!pkg.exists() || !pkg.isFile()) {
        qWarning() << "installFromFile: invalid package path" << packagePath;
        return result;
    }

    // 目标目录必须先存在：解压临时目录建在目标目录内（同一文件系统），
    // 否则 rename(2) 跨文件系统失败（如 /tmp 是 tmpfs、~/.local/share 在 ext4，
    // 返回 EXDEV），安装永远走不到落盘一步。
    QDir().mkpath(destWidgetsDir);

    // 进程崩溃才会残留 .install-* 临时目录；入口处顺手清理，防止累积
    {
        const QDir dest(destWidgetsDir);
        const QStringList stale = dest.entryList(
            QStringList() << QLatin1String(kInstallTmpPrefix) + QLatin1String("*"),
            QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot);
        for (const QString &dir : stale)
            QDir(destWidgetsDir + QLatin1Char('/') + dir).removeRecursively();
    }

    // 点前缀使临时目录对 scanWidgets 不可见（entryList 默认排除隐藏项）；
    // 任一校验失败时 QTemporaryDir 析构自动清除
    QTemporaryDir tmp(destWidgetsDir + QLatin1Char('/')
        + QLatin1String(kInstallTmpPrefix) + QLatin1String("XXXXXX"));
    if (!tmp.isValid()) {
        qWarning() << "installFromFile: cannot create temp dir under" << destWidgetsDir;
        return result;
    }

    // 1. 列出包内容，拒绝路径穿越（.. 或绝对路径）
    QProcess listProc;
    listProc.start("tar", {"-tJf", localPath});
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
    extractProc.start("tar", {"-xJf", localPath, "-C", tmp.path()});
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

    // 5. 移动到安装目录：主路径为同文件系统原子 rename（临时目录已建在
    // destWidgetsDir 内）；极端场景 rename 仍失败时回退深拷贝。
    const QFileInfo mfInfo(manifestPath);
    const QString sourceDir = mfInfo.absolutePath();
    const QString targetDir = destWidgetsDir + "/" + widgetId;
    QDir src(sourceDir);
    if (!src.rename(sourceDir, targetDir)) {
        qWarning() << "installFromFile: rename to" << targetDir
                   << "failed, falling back to deep copy";
        if (QFileInfo::exists(targetDir))
            QDir(targetDir).removeRecursively();
        if (!copyDirRecursively(sourceDir, targetDir) || !src.removeRecursively()) {
            QDir(targetDir).removeRecursively();   // 清掉半成品，避免残留假安装
            qWarning() << "installFromFile: move to" << targetDir << "failed";
            return result;
        }
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
