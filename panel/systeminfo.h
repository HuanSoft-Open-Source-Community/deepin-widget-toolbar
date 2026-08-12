// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QTimer>

// 系统监视数据源（QML 单例 org.deepin.widgettoolbar/SystemInfo）：
// 周期读取 /proc/stat、/proc/meminfo 与根分区磁盘占用。
class SystemInfo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qreal cpuUsage READ cpuUsage NOTIFY refreshed)
    Q_PROPERTY(qreal memUsedPercent READ memUsedPercent NOTIFY refreshed)
    Q_PROPERTY(qreal diskUsedPercent READ diskUsedPercent NOTIFY refreshed)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    qreal cpuUsage() const;
    qreal memUsedPercent() const;
    qreal diskUsedPercent() const;

    Q_INVOKABLE void setRefreshInterval(int ms);

Q_SIGNALS:
    void refreshed();

private:
    void refresh();
    void readCpu();
    void readMem();
    void readDisk();

    QTimer m_timer;
    qreal m_cpuUsage = 0.0;
    qreal m_memUsedPercent = 0.0;
    qreal m_diskUsedPercent = 0.0;

    quint64 m_prevIdle = 0;
    quint64 m_prevTotal = 0;
};
