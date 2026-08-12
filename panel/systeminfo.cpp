// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "systeminfo.h"

#include <QDebug>
#include <QFile>
#include <QStorageInfo>
#include <QTextStream>

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(1000);
    m_timer.setTimerType(Qt::CoarseTimer);
    connect(&m_timer, &QTimer::timeout, this, &SystemInfo::refresh);
    refresh();
    m_timer.start();
}

qreal SystemInfo::cpuUsage() const
{
    return m_cpuUsage;
}

qreal SystemInfo::memUsedPercent() const
{
    return m_memUsedPercent;
}

qreal SystemInfo::diskUsedPercent() const
{
    return m_diskUsedPercent;
}

void SystemInfo::setRefreshInterval(int ms)
{
    m_timer.setInterval(qMax(200, ms));
}

void SystemInfo::refresh()
{
    readCpu();
    readMem();
    readDisk();
    Q_EMIT refreshed();
}

void SystemInfo::readCpu()
{
    // /proc/stat 第一行 "cpu  user nice system idle iowait irq softirq steal ..."
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QByteArray line = f.readLine();
    QList<quint64> vals;
    // /proc/stat 首行为 "cpu  user nice ..."（cpu 后双空格），必须跳过空段
    const QStringList parts = QString::fromUtf8(line).split(' ', Qt::SkipEmptyParts);
    for (const QString &p : parts) {
        bool ok = false;
        const quint64 v = p.toULongLong(&ok);
        if (ok)
            vals.append(v);
    }
    if (vals.size() < 4)
        return;

    quint64 idle = vals.at(3);   // idle
    if (vals.size() > 4)
        idle += vals.at(4);      // iowait
    quint64 total = 0;
    for (quint64 v : vals)
        total += v;

    if (m_prevTotal != 0) {
        const quint64 dTotal = total - m_prevTotal;
        const quint64 dIdle = idle - m_prevIdle;
        if (dTotal > 0)
            m_cpuUsage = qBound<qreal>(0.0, 1.0 - qreal(dIdle) / qreal(dTotal), 1.0);
    }
    m_prevTotal = total;
    m_prevIdle = idle;
}

void SystemInfo::readMem()
{
    // /proc/meminfo：MemTotal / MemAvailable
    QFile f("/proc/meminfo");
    if (!f.open(QIODevice::ReadOnly))
        return;

    quint64 total = 0;
    quint64 available = 0;
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString line = in.readLine();
        if (line.startsWith("MemTotal:"))
            total = line.section(' ', -2, -2).toULongLong();
        else if (line.startsWith("MemAvailable:"))
            available = line.section(' ', -2, -2).toULongLong();
        if (total > 0 && available > 0)
            break;
    }
    if (total > 0)
        m_memUsedPercent = qBound<qreal>(0.0, 1.0 - qreal(available) / qreal(total), 1.0);
}

void SystemInfo::readDisk()
{
    // 根分区占用
    const QStorageInfo root("/");
    if (root.isValid() && root.bytesTotal() > 0) {
        const qreal used = qreal(root.bytesTotal() - root.bytesAvailable());
        m_diskUsedPercent = qBound<qreal>(0.0, used / qreal(root.bytesTotal()), 1.0);
    }
}
