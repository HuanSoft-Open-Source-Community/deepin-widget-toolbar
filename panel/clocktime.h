// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QTimer>

// 预加载时间源（QML 单例 org.deepin.widgettoolbar/ClockTime）：
// 由宿主维护唯一的秒级时钟，按系统整秒对齐后统一广播 epochMs。
// 时钟/世界时钟等小组件订阅该信号即可共享同一时刻，避免每个表盘
// 各自创建 Timer、重复读取系统时间，以及同秒集中重绘造成的卡顿。
class ClockTime : public QObject
{
    Q_OBJECT
    // QML 的数值类型是 double，不直接支持 qint64；当前 Unix 毫秒远小于
    // 2^53，转成 double 可精确表示，避免 QML 侧类型转换/精度问题。
    Q_PROPERTY(double epochMs READ epochMs NOTIFY epochMsChanged)

public:
    explicit ClockTime(QObject *parent = nullptr);

    double epochMs() const;

    // 立即补发一次当前整秒时间（供刚显示的表盘同步，不改变原有周期）
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    // 每次整秒时间变化时发出；同一秒内只广播一次
    void epochMsChanged();

private Q_SLOTS:
    void tick();

private:
    void scheduleNext();

    QTimer m_timer;
    qint64 m_epochMs = 0;
};
