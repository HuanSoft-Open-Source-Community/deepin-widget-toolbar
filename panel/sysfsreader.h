// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QString>
#include <QStringList>

// sysfs 硬件指标的通用读取工具（GPU/NPU 采样共用）：
// 纯函数 + 累积计数器结构，无状态归属。
namespace SysfsReader {

// 累积计数器采样（GPU Xe idle / NPU busy 共用）
struct CumulativeSample {
    quint64 value = 0;
    qint64 timeUs = 0;
};

// 来源重扫描间隔：30s
inline constexpr qint64 kRescanIntervalUs = 30LL * 1000 * 1000;

qint64 nowUs();
qreal clampFraction(qreal value);
bool readFirstNumber(const QString &path, quint64 *out);
bool readFirstLine(const QString &path, QByteArray *out);
QString readTextFile(const QString &path);
bool readPercentFile(const QString &path, qreal *out);
QStringList listSysfsDevices(const QString &dirPath, const QString &prefix);
QString accelDriverName(const QString &device);

// 累积百分比（GPU Xe idle_residency_ms / NPU busy 计数器共用差值逻辑）：
// 首次采样仅建立基线返回 false，之后按 Δ值/Δt 计算占比
bool updateBusyFromIdleMs(const QString &path,
                          QHash<QString, CumulativeSample> *samples,
                          qreal *busy);
bool updateUsageFromBusyUs(const QString &path,
                           QHash<QString, CumulativeSample> *samples,
                           qreal *usage);

} // namespace SysfsReader
