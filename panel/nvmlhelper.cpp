// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "nvmlhelper.h"

#include "sysfsreader.h"

bool NvmlHelper::load()
{
    if (m_library.isLoaded())
        return true;

    m_library.setFileName(QStringLiteral("nvidia-ml.so.1"));
    if (!m_library.load())
        m_library.setFileName(QStringLiteral("nvidia-ml"));
    if (!m_library.isLoaded() && !m_library.load())
        return false;

    m_init = reinterpret_cast<InitFn>(m_library.resolve("nvmlInit_v2"));
    m_shutdown = reinterpret_cast<ShutdownFn>(m_library.resolve("nvmlShutdown"));
    m_deviceGetCount = reinterpret_cast<DeviceGetCountFn>(m_library.resolve("nvmlDeviceGetCount_v2"));
    m_deviceGetHandleByIndex = reinterpret_cast<DeviceGetHandleByIndexFn>(
        m_library.resolve("nvmlDeviceGetHandleByIndex_v2"));
    if (!m_deviceGetHandleByIndex) {
        m_deviceGetHandleByIndex = reinterpret_cast<DeviceGetHandleByIndexFn>(
            m_library.resolve("nvmlDeviceGetHandleByIndex"));
    }
    m_deviceGetUtilizationRates = reinterpret_cast<DeviceGetUtilizationRatesFn>(
        m_library.resolve("nvmlDeviceGetUtilizationRates"));

    return m_init && m_deviceGetCount && m_deviceGetHandleByIndex
        && m_deviceGetUtilizationRates;
}

bool NvmlHelper::readGpuUsage(qreal *out)
{
    if (!m_initAttempted) {
        m_initAttempted = true;
        if (load() && m_init() == 0)
            m_available = true;
    }
    if (!m_available)
        return false;

    unsigned int count = 0;
    if (m_deviceGetCount(&count) != 0 || count == 0)
        return false;

    unsigned int best = 0;
    for (unsigned int i = 0; i < count; ++i) {
        Device device = nullptr;
        Utilization utilization;
        if (m_deviceGetHandleByIndex(i, &device) != 0)
            continue;
        if (m_deviceGetUtilizationRates(device, &utilization) != 0)
            continue;
        best = qMax(best, utilization.gpu);
    }
    *out = SysfsReader::clampFraction(qreal(best) / 100.0);
    return true;
}
