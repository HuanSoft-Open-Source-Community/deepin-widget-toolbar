// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QLibrary>

// NVIDIA NVML 读取器：运行时动态加载（无编译期依赖），
// 惰性初始化后读取全部 GPU 中的最高利用率。
class NvmlHelper
{
public:
    // 惰性加载 libnvidia-ml 并初始化；失败返回 false（后续调用不再重试）
    bool load();
    // 读取多 GPU 中最高利用率（0..1）；未加载/无设备返回 false
    bool readGpuUsage(qreal *out);

private:
    struct Utilization {
        unsigned int gpu = 0;
        unsigned int memory = 0;
    };
    using Return = int;
    using Device = void *;
    using InitFn = Return (*)();
    using ShutdownFn = Return (*)();
    using DeviceGetCountFn = Return (*)(unsigned int *);
    using DeviceGetHandleByIndexFn = Return (*)(unsigned int, Device *);
    using DeviceGetUtilizationRatesFn = Return (*)(Device, Utilization *);

    QLibrary m_library;
    InitFn m_init = nullptr;
    ShutdownFn m_shutdown = nullptr;
    DeviceGetCountFn m_deviceGetCount = nullptr;
    DeviceGetHandleByIndexFn m_deviceGetHandleByIndex = nullptr;
    DeviceGetUtilizationRatesFn m_deviceGetUtilizationRates = nullptr;
    bool m_initAttempted = false;
    bool m_available = false;
};
