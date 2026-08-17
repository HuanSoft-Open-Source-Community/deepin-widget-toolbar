// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "systeminfoworker.h"

#include "sysfsreader.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStorageInfo>

#include <unistd.h>


SystemInfoWorker::SystemInfoWorker(QObject *parent)
    : QObject(parent)
{
}

bool SystemInfoWorker::metricEnabled(const QString &metricId) const
{
    return m_metrics.contains(metricId);
}

void SystemInfoWorker::setState(bool active, const QStringList &metrics,
                                int intervalMs)
{
    // setState 经 QueuedConnection 只在工作线程执行：首次调用时把定时器
    // 创建在当前线程，确保定时器与采样循环线程亲和性一致。
    if (!m_timer) {
        m_timer = new QTimer(this);
        m_timer->setTimerType(Qt::CoarseTimer);
        connect(m_timer, &QTimer::timeout, this, &SystemInfoWorker::sample);
    }

    m_active = active;
    m_metrics.clear();
    for (const QString &metric : metrics) {
        const QString normalized = metric.trimmed().toLower();
        if (!normalized.isEmpty())
            m_metrics.insert(normalized);
    }

    m_timer->setInterval(qMax(1000, intervalMs));

    if (!m_active || m_metrics.isEmpty()) {
        m_timer->stop();
        return;
    }

    sample();
    if (!m_timer->isActive())
        m_timer->start();
}

void SystemInfoWorker::sample()
{
    if (!m_active || m_metrics.isEmpty())
        return;

    if (metricEnabled(QStringLiteral("cpu")))
        readCpu();
    if (metricEnabled(QStringLiteral("mem")))
        readMem();
    if (metricEnabled(QStringLiteral("diskUsed")))
        readDisk();
    if (metricEnabled(QStringLiteral("disk")))
        readDiskIO();
    if (metricEnabled(QStringLiteral("gpu")))
        readGpu();
    if (metricEnabled(QStringLiteral("npu")))
        readNpu();

    Q_EMIT sampleReady(m_cpuUsage, m_memUsedPercent, m_diskUsedPercent,
                       m_diskBusyPercent, m_gpuUsage, m_gpuAvailable,
                       m_npuUsage, m_npuAvailable);
}

void SystemInfoWorker::readCpu()
{
    // /proc/stat 第一行 "cpu  user nice system idle iowait irq softirq steal ..."
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QByteArray line = f.readLine();
    QList<quint64> vals;
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
            m_cpuUsage = SysfsReader::clampFraction(1.0 - qreal(dIdle) / qreal(dTotal));
    }
    m_prevTotal = total;
    m_prevIdle = idle;
}

void SystemInfoWorker::readMem()
{
    QFile f("/proc/meminfo");
    if (!f.open(QIODevice::ReadOnly))
        return;

    quint64 total = 0;
    quint64 available = 0;
    const QStringList lines = QString::fromUtf8(f.readAll()).split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QStringList parts = line.simplified().split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 2)
            continue;
        if (parts.at(0) == QLatin1String("MemTotal:")) {
            total = parts.at(1).toULongLong();
        } else if (parts.at(0) == QLatin1String("MemAvailable:")) {
            available = parts.at(1).toULongLong();
        }
        if (total > 0 && available > 0)
            break;
    }
    if (total > 0)
        m_memUsedPercent = SysfsReader::clampFraction(1.0 - qreal(available) / qreal(total));
}

void SystemInfoWorker::readDisk()
{
    // 根分区占用：保留给旧接口，资源监视面板不再展示此项。
    const QStorageInfo root("/");
    if (root.isValid() && root.bytesTotal() > 0) {
        const qreal used = qreal(root.bytesTotal() - root.bytesAvailable());
        m_diskUsedPercent = SysfsReader::clampFraction(used / qreal(root.bytesTotal()));
    }
}

void SystemInfoWorker::refreshDiskDevices()
{
    m_diskDevices.clear();
    QFile f("/proc/diskstats");
    if (!f.open(QIODevice::ReadOnly))
        return;

    static const QStringList prefixes = {
        QStringLiteral("nvme"), QStringLiteral("sd"), QStringLiteral("mmcblk"),
        QStringLiteral("vd"), QStringLiteral("xvd"),
    };
    while (!f.atEnd()) {
        const QStringList parts = QString::fromUtf8(f.readLine())
                                      .simplified()
                                      .split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 3)
            continue;
        const QString name = parts.at(2);
        bool physical = false;
        for (const QString &prefix : prefixes) {
            if (name.startsWith(prefix)) {
                physical = true;
                break;
            }
        }
        if (!physical)
            continue;
        if (QFileInfo::exists(QStringLiteral("/sys/class/block/") + name
                              + QStringLiteral("/partition"))) {
            continue;
        }
        m_diskDevices.insert(name);
    }
    m_diskDevicesRefreshedUs = SysfsReader::nowUs();
}

void SystemInfoWorker::readDiskIO()
{
    if (m_clockTicksPerSecond <= 0) {
        m_clockTicksPerSecond = sysconf(_SC_CLK_TCK);
        if (m_clockTicksPerSecond <= 0)
            m_clockTicksPerSecond = 100;
    }

    const qint64 now = SysfsReader::nowUs();
    if (m_diskDevices.isEmpty() || now - m_diskDevicesRefreshedUs > SysfsReader::kRescanIntervalUs)
        refreshDiskDevices();

    QFile f("/proc/diskstats");
    if (!f.open(QIODevice::ReadOnly))
        return;

    quint64 busyTicks = 0;
    while (!f.atEnd()) {
        const QStringList parts = QString::fromUtf8(f.readLine())
                                      .simplified()
                                      .split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 13)
            continue;
        if (!m_diskDevices.contains(parts.at(2)))
            continue;
        busyTicks += parts.at(12).toULongLong();
    }

    if (m_prevDiskTimeUs > 0 && now > m_prevDiskTimeUs) {
        const quint64 deltaTicks = busyTicks >= m_prevDiskBusyTicks
            ? busyTicks - m_prevDiskBusyTicks : 0;
        const qreal elapsedSeconds = qreal(now - m_prevDiskTimeUs) / 1000000.0;
        const qreal busySeconds = qreal(deltaTicks) / qreal(m_clockTicksPerSecond);
        m_diskBusyPercent = SysfsReader::clampFraction(busySeconds / elapsedSeconds);
    } else {
        m_diskBusyPercent = 0.0;
    }
    m_prevDiskBusyTicks = busyTicks;
    m_prevDiskTimeUs = now;
}

void SystemInfoWorker::readGpu()
{
    m_gpuUsage = 0.0;
    m_gpuAvailable = false;

    qreal value = 0.0;
    if (m_gpu.read(&value)) {
        m_gpuUsage = value;
        m_gpuAvailable = true;
        return;
    }
    // 缓存来源失效或尚未定位：按固定间隔重扫描（来源定位在 GpuHelper 内部）
    if (m_gpu.scanIfDue(&value)) {
        m_gpuUsage = value;
        m_gpuAvailable = true;
    }
}

void SystemInfoWorker::readNpu()
{
    m_npuUsage = 0.0;
    m_npuAvailable = false;

    qreal value = 0.0;
    if (m_npu.read(&value)) {
        m_npuUsage = value;
        m_npuAvailable = true;
        return;
    }
    // 缓存来源失效或尚未定位：按固定间隔重扫描（来源定位在 NpuHelper 内部）
    if (m_npu.scanIfDue(&value)) {
        m_npuUsage = value;
        m_npuAvailable = true;
    }
}
