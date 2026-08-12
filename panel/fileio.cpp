// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fileio.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>

FileIO::FileIO(QObject *parent)
    : QObject(parent)
{
}

void FileIO::setAllowedRoot(const QString &path)
{
    m_allowedRoot = QDir(path).absolutePath();
}

bool FileIO::isAllowed(const QString &path) const
{
    if (m_allowedRoot.isEmpty()) {
        qWarning() << "FileIO: allowed root not set, denying access";
        return false;
    }
    const QString canonical = QFileInfo(path).canonicalFilePath();
    if (canonical.isEmpty()) {
        // 文件尚不存在时 canonical 为空，用绝对路径前缀判断（写入场景）
        const QString abs = QFileInfo(path).absolutePath();
        return abs.startsWith(m_allowedRoot + "/") || abs == m_allowedRoot;
    }
    return canonical.startsWith(m_allowedRoot + "/") || canonical == m_allowedRoot;
}

QString FileIO::readTextFile(const QString &path) const
{
    if (!isAllowed(path)) {
        qWarning() << "FileIO: access denied for" << path;
        return QString();
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(f.readAll());
}

bool FileIO::writeTextFile(const QString &path, const QString &content) const
{
    if (!isAllowed(path)) {
        qWarning() << "FileIO: access denied for" << path;
        return false;
    }

    QFileInfo info(path);
    if (!info.dir().exists() && !QDir().mkpath(info.absolutePath()))
        return false;

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(content.toUtf8());
    return true;
}

bool FileIO::exists(const QString &path) const
{
    if (!isAllowed(path)) {
        qWarning() << "FileIO: access denied for" << path;
        return false;
    }
    return QFile::exists(path);
}
