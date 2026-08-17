// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gpuhelper.h"

#include <QFileInfo>

bool GpuHelper::read(qreal *usage)
{
    qreal value = 0.0;
    switch (m_source) {
    case Source::Nvml:
        if (m_nvml.readGpuUsage(&value)) {
            *usage = value;
            return true;
        }
        break;
    case Source::PercentPath:
        if (SysfsReader::readPercentFile(m_path, &value)) {
            *usage = value;
            return true;
        }
        break;
    case Source::XeIdlePath:
        if (SysfsReader::updateBusyFromIdleMs(m_path, &m_samples, &value)) {
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

bool GpuHelper::scanIfDue(qreal *usage)
{
    const qint64 now = SysfsReader::nowUs();
    if (m_lastScanUs != 0 && now - m_lastScanUs < SysfsReader::kRescanIntervalUs)
        return false;
    m_lastScanUs = now;
    return scan(usage);
}

bool GpuHelper::scan(qreal *usage)
{
    qreal nvmlUsage = 0.0;
    if (m_nvml.readGpuUsage(&nvmlUsage)) {
        m_source = Source::Nvml;
        *usage = nvmlUsage;
        return true;
    }

    qreal best = 0.0;
    bool found = false;
    const QStringList cards = SysfsReader::listSysfsDevices(QStringLiteral("/sys/class/drm"), QStringLiteral("card"));
    for (const QString &card : cards) {
        const QString vendor = SysfsReader::readTextFile(card + QStringLiteral("/device/vendor"));
        const bool intel = vendor == QLatin1String("0x8086");

        QStringList percentPaths;
        if (intel) {
            percentPaths.append(card + QStringLiteral("/gt/gt0/gt_busy_percent"));
            percentPaths.append(card + QStringLiteral("/device/gt/gt0/gt_busy_percent"));
            percentPaths.append(card + QStringLiteral("/gt/gt0/media_busy_percent"));
            percentPaths.append(card + QStringLiteral("/device/gt/gt0/media_busy_percent"));
        }
        percentPaths.append(card + QStringLiteral("/gpu_busy_percent"));
        percentPaths.append(card + QStringLiteral("/device/gpu_busy_percent"));

        bool hasPercent = false;
        for (const QString &path : percentPaths) {
            qreal value = 0.0;
            if (SysfsReader::readPercentFile(path, &value)) {
                best = qMax(best, value);
                found = true;
                hasPercent = true;
                m_source = Source::PercentPath;
                m_path = path;
                break;
            }
        }

        // AMD 无 gpu_busy_percent 时按调研回退 hwmon/busy。
        if (!hasPercent && !intel) {
            const QString hwmonRoot = card + QStringLiteral("/device/hwmon");
            const QStringList hwmons = SysfsReader::listSysfsDevices(hwmonRoot, QStringLiteral("hwmon"));
            for (const QString &hwmon : hwmons) {
                const QString path = hwmon + QStringLiteral("/busy");
                qreal value = 0.0;
                if (SysfsReader::readPercentFile(path, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_source = Source::PercentPath;
                    m_path = path;
                    break;
                }
            }
        }

        // Intel Xe 没有标准 busy_percent，改用 idle_residency_ms 累积差值。
        if (intel && !hasPercent) {
            const QStringList xeIdleCandidates = {
                card + QStringLiteral("/device/tile0/gt0/gtidle/idle_residency_ms"),
                card + QStringLiteral("/device/gt0/gtidle/idle_residency_ms"),
                card + QStringLiteral("/gt/gt0/gtidle/idle_residency_ms"),
            };
            for (const QString &path : xeIdleCandidates) {
                qreal value = 0.0;
                if (SysfsReader::updateBusyFromIdleMs(path, &m_samples, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_source = Source::XeIdlePath;
                    m_path = path;
                    break;
                }
                // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
                if (QFileInfo::exists(path)) {
                    m_source = Source::XeIdlePath;
                    m_path = path;
                    break;
                }
            }
        }
        if (found)
            break;
    }

    if (found)
        *usage = best;
    return found;
}
