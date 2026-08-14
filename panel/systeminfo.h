// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QTimer>

// 系统监视数据源（QML 单例 org.deepin.widgettoolbar/SystemInfo）：
// 周期读取 /proc/stat、/proc/meminfo、/proc/diskstats、DRM/accel sysfs
// 与可选的 NVIDIA NVML。具体公式与数据来源见 docs/system-monitor.md。
class SystemInfo : public QObject
{
    Q_OBJECT
public:
    // 累积计数器采样（GPU Xe idle / NPU busy 共用）
    struct CumulativeSample {
        quint64 value = 0;
        qint64 timeUs = 0;
    };

    Q_PROPERTY(qreal cpuUsage READ cpuUsage NOTIFY refreshed)
    Q_PROPERTY(qreal memUsedPercent READ memUsedPercent NOTIFY refreshed)
    // 兼容旧接口：根分区空间占用率，仅保留给第三方旧小组件。
    Q_PROPERTY(qreal diskUsedPercent READ diskUsedPercent NOTIFY refreshed)
    // iostat 风格的磁盘 IO 忙时利用率（0~1）
    Q_PROPERTY(qreal diskBusyPercent READ diskBusyPercent NOTIFY refreshed)
    Q_PROPERTY(qreal gpuUsage READ gpuUsage NOTIFY refreshed)
    Q_PROPERTY(bool gpuAvailable READ gpuAvailable NOTIFY refreshed)
    Q_PROPERTY(qreal npuUsage READ npuUsage NOTIFY refreshed)
    Q_PROPERTY(bool npuAvailable READ npuAvailable NOTIFY refreshed)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    qreal cpuUsage() const;
    qreal memUsedPercent() const;
    qreal diskUsedPercent() const;
    qreal diskBusyPercent() const;
    qreal gpuUsage() const;
    bool gpuAvailable() const;
    qreal npuUsage() const;
    bool npuAvailable() const;

    Q_INVOKABLE void setRefreshInterval(int ms);

Q_SIGNALS:
    void refreshed();

private:
    void refresh();
    void readCpu();
    void readMem();
    void readDisk();
    void readDiskIO();
    void readGpu();
    void readNpu();

    QTimer m_timer;
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

    // key 为 sysfs 文件路径；GPU(Xe idle) 与 NPU 的累积计数器共用
    QHash<QString, CumulativeSample> m_cumulativeSamples;
};
