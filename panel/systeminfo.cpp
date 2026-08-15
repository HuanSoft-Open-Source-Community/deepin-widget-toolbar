// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "systeminfo.h"

#include "systeminfoworker.h"

#include <QMetaObject>
#include <QSet>
#include <QThread>
#include <QTimer>

#include <algorithm>

namespace {

QStringList normalizeMetrics(const QStringList &metrics)
{
    QSet<QString> result;
    for (const QString &metric : metrics) {
        const QString normalized = metric.trimmed().toLower();
        if (!normalized.isEmpty())
            result.insert(normalized);
    }

    QStringList list = result.values();
    std::sort(list.begin(), list.end());
    return list;
}

} // namespace

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
{
    m_workerThread = new QThread(this);
    m_worker = new SystemInfoWorker();
    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(m_worker, &SystemInfoWorker::sampleReady,
            this, &SystemInfo::applySample);

    m_workerThread->start();
}

SystemInfo::~SystemInfo()
{
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait();
    }
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

qreal SystemInfo::diskBusyPercent() const
{
    return m_diskBusyPercent;
}

qreal SystemInfo::gpuUsage() const
{
    return m_gpuUsage;
}

bool SystemInfo::gpuAvailable() const
{
    return m_gpuAvailable;
}

qreal SystemInfo::npuUsage() const
{
    return m_npuUsage;
}

bool SystemInfo::npuAvailable() const
{
    return m_npuAvailable;
}

void SystemInfo::setRefreshInterval(int ms)
{
    auto &request = m_requests[QStringLiteral("__legacy__")];
    request.intervalMs = qMax(1000, ms);
    scheduleApplyRequest();
}

void SystemInfo::setMonitoringActive(bool active)
{
    auto &request = m_requests[QStringLiteral("__legacy__")];
    request.active = active;
    scheduleApplyRequest();
}

void SystemInfo::setMonitoredMetrics(const QStringList &metrics)
{
    auto &request = m_requests[QStringLiteral("__legacy__")];
    request.metrics = normalizeMetrics(metrics);
    scheduleApplyRequest();
}

void SystemInfo::updateMonitor(const QString &clientId, bool active,
                               const QStringList &metrics, int intervalMs)
{
    const QString id = clientId.trimmed();
    if (id.isEmpty())
        return;

    auto &request = m_requests[id];
    request.active = active;
    request.metrics = normalizeMetrics(metrics);
    request.intervalMs = qMax(1000, intervalMs);
    scheduleApplyRequest();
}

void SystemInfo::releaseMonitor(const QString &clientId)
{
    const QString id = clientId.trimmed();
    if (id.isEmpty())
        return;

    if (m_requests.remove(id) > 0)
        scheduleApplyRequest();
}

void SystemInfo::scheduleApplyRequest()
{
    if (m_applyPending)
        return;

    m_applyPending = true;
    QTimer::singleShot(0, this, &SystemInfo::applyRequest);
}

void SystemInfo::applyRequest()
{
    m_applyPending = false;

    bool anyActive = false;
    QSet<QString> metricSet;
    int minInterval = 5000;
    for (auto it = m_requests.cbegin(); it != m_requests.cend(); ++it) {
        const MonitorRequest &request = it.value();
        if (!request.active || request.metrics.isEmpty())
            continue;

        anyActive = true;
        minInterval = qMin(minInterval, request.intervalMs);
        for (const QString &metric : request.metrics)
            metricSet.insert(metric);
    }

    QStringList metrics = metricSet.values();
    std::sort(metrics.begin(), metrics.end());

    QMetaObject::invokeMethod(m_worker, "setState",
                              Qt::QueuedConnection,
                              Q_ARG(bool, anyActive),
                              Q_ARG(QStringList, metrics),
                              Q_ARG(int, qMax(1000, anyActive ? minInterval : 5000)));
}

void SystemInfo::applySample(qreal cpuUsage, qreal memUsedPercent,
                             qreal diskUsedPercent, qreal diskBusyPercent,
                             qreal gpuUsage, bool gpuAvailable,
                             qreal npuUsage, bool npuAvailable)
{
    constexpr qreal kUpdateThreshold = 0.005;
    bool changed = false;

    if (qAbs(cpuUsage - m_cpuUsage) >= kUpdateThreshold) {
        m_cpuUsage = cpuUsage;
        Q_EMIT cpuUsageChanged();
        changed = true;
    }
    if (qAbs(memUsedPercent - m_memUsedPercent) >= kUpdateThreshold) {
        m_memUsedPercent = memUsedPercent;
        Q_EMIT memUsedPercentChanged();
        changed = true;
    }
    if (qAbs(diskUsedPercent - m_diskUsedPercent) >= kUpdateThreshold) {
        m_diskUsedPercent = diskUsedPercent;
        Q_EMIT diskUsedPercentChanged();
        changed = true;
    }
    if (qAbs(diskBusyPercent - m_diskBusyPercent) >= kUpdateThreshold) {
        m_diskBusyPercent = diskBusyPercent;
        Q_EMIT diskBusyPercentChanged();
        changed = true;
    }
    if (qAbs(gpuUsage - m_gpuUsage) >= kUpdateThreshold) {
        m_gpuUsage = gpuUsage;
        Q_EMIT gpuUsageChanged();
        changed = true;
    }
    if (gpuAvailable != m_gpuAvailable) {
        m_gpuAvailable = gpuAvailable;
        Q_EMIT gpuAvailableChanged();
        changed = true;
    }
    if (qAbs(npuUsage - m_npuUsage) >= kUpdateThreshold) {
        m_npuUsage = npuUsage;
        Q_EMIT npuUsageChanged();
        changed = true;
    }
    if (npuAvailable != m_npuAvailable) {
        m_npuAvailable = npuAvailable;
        Q_EMIT npuAvailableChanged();
        changed = true;
    }

    if (changed)
        Q_EMIT refreshed();
}
