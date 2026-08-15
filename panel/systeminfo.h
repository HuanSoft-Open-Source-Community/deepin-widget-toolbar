// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>

class QThread;
class SystemInfoWorker;

// 系统监视数据源（QML 单例 org.deepin.widgettoolbar/SystemInfo）：
// 文件/sysfs/NVML 采样在工作线程执行，结果通过 queued signal 回传后更新 QML 属性。
// 新组件通过 updateMonitor(clientId, ...) 注册自身需求，SystemInfo 合并所有活动
// 客户端的指标集合并按最小刷新间隔采样；旧的无参接口继续兼容。
class SystemInfo : public QObject
{
    Q_OBJECT
public:
    Q_PROPERTY(qreal cpuUsage READ cpuUsage NOTIFY cpuUsageChanged)
    Q_PROPERTY(qreal memUsedPercent READ memUsedPercent NOTIFY memUsedPercentChanged)
    // 兼容旧接口：根分区空间占用率，仅保留给第三方旧小组件。
    Q_PROPERTY(qreal diskUsedPercent READ diskUsedPercent NOTIFY diskUsedPercentChanged)
    // iostat 风格的磁盘 IO 忙时利用率（0~1）
    Q_PROPERTY(qreal diskBusyPercent READ diskBusyPercent NOTIFY diskBusyPercentChanged)
    Q_PROPERTY(qreal gpuUsage READ gpuUsage NOTIFY gpuUsageChanged)
    Q_PROPERTY(bool gpuAvailable READ gpuAvailable NOTIFY gpuAvailableChanged)
    Q_PROPERTY(qreal npuUsage READ npuUsage NOTIFY npuUsageChanged)
    Q_PROPERTY(bool npuAvailable READ npuAvailable NOTIFY npuAvailableChanged)

    explicit SystemInfo(QObject *parent = nullptr);
    ~SystemInfo() override;

    qreal cpuUsage() const;
    qreal memUsedPercent() const;
    qreal diskUsedPercent() const;
    qreal diskBusyPercent() const;
    qreal gpuUsage() const;
    bool gpuAvailable() const;
    qreal npuUsage() const;
    bool npuAvailable() const;

    Q_INVOKABLE void setRefreshInterval(int ms);
    Q_INVOKABLE void setMonitoringActive(bool active);
    Q_INVOKABLE void setMonitoredMetrics(const QStringList &metrics);
    // 以 clientId 注册/更新监控需求；clientId 为空时忽略。
    Q_INVOKABLE void updateMonitor(const QString &clientId, bool active,
                                   const QStringList &metrics, int intervalMs);
    Q_INVOKABLE void releaseMonitor(const QString &clientId);

Q_SIGNALS:
    // 各属性独立通知信号；refreshed 保留为任一指标变化时的兼容信号。
    void cpuUsageChanged();
    void memUsedPercentChanged();
    void diskUsedPercentChanged();
    void diskBusyPercentChanged();
    void gpuUsageChanged();
    void gpuAvailableChanged();
    void npuUsageChanged();
    void npuAvailableChanged();
    void refreshed();

private Q_SLOTS:
    void applySample(qreal cpuUsage, qreal memUsedPercent, qreal diskUsedPercent,
                     qreal diskBusyPercent, qreal gpuUsage, bool gpuAvailable,
                     qreal npuUsage, bool npuAvailable);
    void applyRequest();

private:
    struct MonitorRequest {
        bool active = false;
        QStringList metrics;
        int intervalMs = 5000;
    };

    void scheduleApplyRequest();

    QThread *m_workerThread = nullptr;
    SystemInfoWorker *m_worker = nullptr;
    QHash<QString, MonitorRequest> m_requests;
    bool m_applyPending = false;

    qreal m_cpuUsage = 0.0;
    qreal m_memUsedPercent = 0.0;
    qreal m_diskUsedPercent = 0.0;
    qreal m_diskBusyPercent = 0.0;
    qreal m_gpuUsage = 0.0;
    bool m_gpuAvailable = false;
    qreal m_npuUsage = 0.0;
    bool m_npuAvailable = false;
};
