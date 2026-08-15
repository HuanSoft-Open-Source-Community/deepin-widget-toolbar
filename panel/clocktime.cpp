// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "clocktime.h"

#include <QDateTime>
#include <QTime>

ClockTime::ClockTime(QObject *parent)
    : QObject(parent)
{
    m_timer.setSingleShot(true);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &ClockTime::tick);

    tick();
}

double ClockTime::epochMs() const
{
    return static_cast<double>(m_epochMs);
}

void ClockTime::refresh()
{
    tick();
}

void ClockTime::tick()
{
    const qint64 ms = QDateTime::currentMSecsSinceEpoch();
    if (ms != m_epochMs) {
        m_epochMs = ms;
        Q_EMIT epochMsChanged();
    }
    scheduleNext();
}

void ClockTime::scheduleNext()
{
    // 每次都在当前秒末重排下一次触发，使广播始终对齐系统整秒，
    // 而不是从启动时刻起累积 1000ms 的相位漂移。
    const int msecToNextSecond = 1000 - QTime::currentTime().msec();
    m_timer.start(msecToNextSecond);
}
