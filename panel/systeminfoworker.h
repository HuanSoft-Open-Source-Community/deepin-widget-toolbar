// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QTimer>

// 在独立线程中读取系统硬件指标的工作对象。
// 只采样被 setState() 请求的指标，并在 GPU/NPU 首次定位后缓存来源路径。
class SystemInfoWorker : public QObject
{
    Q_OBJECT
public:
    // 累积计数器采样（GPU Xe idle / NPU busy 共用）
    struct CumulativeSample {
        quint64 value = 0;
        qint64 timeUs = 0;
    };

    explicit SystemInfoWorker(QObject *parent = nullptr);

public Q_SLOTS:
    // 原子更新采样开关、指标集合与刷新间隔，保证每次状态变化最多采样一次。
    void setState(bool active, const QStringList &metrics, int intervalMs);

Q_SIGNALS:
    void sampleReady(qreal cpuUsage, qreal memUsedPercent, qreal diskUsedPercent,
                     qreal diskBusyPercent, qreal gpuUsage, bool gpuAvailable,
                     qreal npuUsage, bool npuAvailable);

private Q_SLOTS:
    void sample();

private:
    enum class GpuSource { None, Nvml, PercentPath, XeIdlePath };
    enum class NpuSource { None, PercentPath, CumulativePath };

    bool metricEnabled(const QString &metricId) const;

    void readCpu();
    void readMem();
    void readDisk();
    void readDiskIO();
    void readGpu();
    void readNpu();

    void refreshDiskDevices();
    bool readCachedGpu();
    bool readCachedNpu();
    bool scanGpu();
    bool scanNpu();

    // 必须在工作线程内创建：SystemInfoWorker 在主线程构造后被 moveToThread，
    // 若 QTimer 在构造时创建，它会保持主线程亲和性，随后在工作线程 start()
    // 会触发 "Timers cannot be started from another thread" 且定时刷新失效。
    QTimer *m_timer = nullptr;
    bool m_active = false;
    QSet<QString> m_metrics;

    qreal m_cpuUsage = 0.0;
    qreal m_memUsedPercent = 0.0;
    qreal m_diskUsedPercent = 0.0;
    qreal m_diskBusyPercent = 0.0;
    qreal m_gpuUsage = 0.0;
    bool m_gpuAvailable = false;
    qreal m_npuUsage = 0.0;
    bool m_npuAvailable = false;

    quint64 m_prevIdle = 0;
    quint64 m_prevTotal = 0;

    quint64 m_prevDiskBusyTicks = 0;
    qint64 m_prevDiskTimeUs = 0;
    long m_clockTicksPerSecond = 0;
    QSet<QString> m_diskDevices;
    qint64 m_diskDevicesRefreshedUs = 0;

    // key 为 sysfs 文件路径；GPU(Xe idle) 与 NPU 的累积计数器共用
    QHash<QString, CumulativeSample> m_cumulativeSamples;

    GpuSource m_gpuSource = GpuSource::None;
    QString m_gpuPath;
    qint64 m_gpuLastScanUs = 0;
    NpuSource m_npuSource = NpuSource::None;
    QString m_npuPath;
    qint64 m_npuLastScanUs = 0;
};
