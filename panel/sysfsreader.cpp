// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "sysfsreader.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <chrono>

namespace SysfsReader {

qint64 nowUs()
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

qreal clampFraction(qreal value)
{
    return qBound<qreal>(0.0, value, 1.0);
}

bool readFirstNumber(const QString &path, quint64 *out)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    bool ok = false;
    const quint64 value = f.readLine().trimmed().toULongLong(&ok);
    if (ok)
        *out = value;
    return ok;
}

bool readFirstLine(const QString &path, QByteArray *out)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    *out = f.readLine().trimmed();
    return true;
}

QString readTextFile(const QString &path)
{
    QByteArray line;
    return readFirstLine(path, &line) ? QString::fromUtf8(line) : QString();
}

bool readPercentFile(const QString &path, qreal *out)
{
    quint64 value = 0;
    if (!readFirstNumber(path, &value))
        return false;
    *out = clampFraction(qreal(value) / 100.0);
    return true;
}

QStringList listSysfsDevices(const QString &dirPath, const QString &prefix)
{
    QStringList result;
    const QDir dir(dirPath);
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        if (entry.startsWith(prefix) && QFileInfo(dirPath + QLatin1Char('/') + entry).isDir())
            result.append(dirPath + QLatin1Char('/') + entry);
    }
    return result;
}

QString accelDriverName(const QString &device)
{
    const QFileInfo link(device + QStringLiteral("/device/driver"));
    if (link.exists())
        return QFileInfo(link.symLinkTarget()).fileName();
    return QString();
}

bool updateBusyFromIdleMs(const QString &path,
                          QHash<QString, CumulativeSample> *samples,
                          qreal *busy)
{
    quint64 idleMs = 0;
    if (!readFirstNumber(path, &idleMs))
        return false;

    const qint64 now = nowUs();
    auto it = samples->find(path);
    if (it == samples->end()) {
        samples->insert(path, {idleMs, now});
        return false;
    }
    const qint64 dtUs = now - it->timeUs;
    const quint64 dIdleMs = idleMs >= it->value ? idleMs - it->value : 0;
    it->value = idleMs;
    it->timeUs = now;
    if (dtUs <= 0)
        return false;

    // idle_residency_ms 为累积毫秒：busy = 1 - Δidle/Δtime。
    const qreal idleFraction = qreal(dIdleMs) / (qreal(dtUs) / 1000.0);
    *busy = clampFraction(1.0 - idleFraction);
    return true;
}

bool updateUsageFromBusyUs(const QString &path,
                           QHash<QString, CumulativeSample> *samples,
                           qreal *usage)
{
    quint64 busyUs = 0;
    if (!readFirstNumber(path, &busyUs))
        return false;

    const qint64 now = nowUs();
    auto it = samples->find(path);
    if (it == samples->end()) {
        samples->insert(path, {busyUs, now});
        return false;
    }
    const qint64 dtUs = now - it->timeUs;
    const quint64 dBusyUs = busyUs >= it->value ? busyUs - it->value : 0;
    it->value = busyUs;
    it->timeUs = now;
    if (dtUs <= 0)
        return false;

    *usage = clampFraction(qreal(dBusyUs) / qreal(dtUs));
    return true;
}

} // namespace SysfsReader
