// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "npuhelper.h"

#include <QFileInfo>

bool NpuHelper::read(qreal *usage)
{
    qreal value = 0.0;
    switch (m_source) {
    case Source::PercentPath:
        if (SysfsReader::readPercentFile(m_path, &value)) {
            *usage = value;
            return true;
        }
        break;
    case Source::CumulativePath:
        if (SysfsReader::updateUsageFromBusyUs(m_path, &m_samples, &value)) {
            *usage = value;
            return true;
        }
        // 首次采样仅建立基线，保持已定位的累积路径，下一周期再计算。
        return false;
    case Source::None:
        return false;
    }

    m_source = Source::None;
    m_path.clear();
    m_lastScanUs = 0;
    return false;
}

bool NpuHelper::scanIfDue(qreal *usage)
{
    const qint64 now = SysfsReader::nowUs();
    if (m_lastScanUs != 0 && now - m_lastScanUs < SysfsReader::kRescanIntervalUs)
        return false;
    m_lastScanUs = now;
    return scan(usage);
}

bool NpuHelper::scan(qreal *usage)
{
    qreal best = 0.0;
    bool found = false;
    const QStringList devices = SysfsReader::listSysfsDevices(QStringLiteral("/sys/class/accel"), QStringLiteral("accel"));
    for (const QString &device : devices) {
        const QString driver = SysfsReader::accelDriverName(device);
        const QString vendor = SysfsReader::readTextFile(device + QStringLiteral("/device/vendor"));

        // 优先 Intel NPU 的累积忙时计数器。
        const QString busyTimeUs = device + QStringLiteral("/device/npu_busy_time_us");
        if (driver == QLatin1String("intel_vpu") || vendor == QLatin1String("0x8086")) {
            qreal value = 0.0;
            if (SysfsReader::updateUsageFromBusyUs(busyTimeUs, &m_samples, &value)) {
                best = qMax(best, value);
                found = true;
                m_source = Source::CumulativePath;
                m_path = busyTimeUs;
                continue;
            }
            // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
            if (QFileInfo::exists(busyTimeUs)) {
                m_source = Source::CumulativePath;
                m_path = busyTimeUs;
                continue;
            }
        }

        // AMD/Rockchip 等无统一接口：按候选忙时文件依次尝试，缺失则不伪造数值。
        const QStringList candidates = {
            device + QStringLiteral("/device/npu_busy_percent"),
            busyTimeUs,
            device + QStringLiteral("/device/usage"),
            device + QStringLiteral("/device/npu_usage"),
        };
        for (const QString &path : candidates) {
            qreal value = 0.0;
            if (path == busyTimeUs) {
                if (SysfsReader::updateUsageFromBusyUs(path, &m_samples, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_source = Source::CumulativePath;
                    m_path = path;
                    break;
                }
                // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
                if (QFileInfo::exists(path)) {
                    m_source = Source::CumulativePath;
                    m_path = path;
                    break;
                }
            } else if (SysfsReader::readPercentFile(path, &value)) {
                best = qMax(best, value);
                found = true;
                m_source = Source::PercentPath;
                m_path = path;
                break;
            }
        }
        if (found)
            break;
    }

    if (found)
        *usage = best;
    return found;
}
