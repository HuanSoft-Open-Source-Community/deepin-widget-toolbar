// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>

#include <functional>
#include <cstddef>

// 音频采集后端抽象：负责从当前系统的音频服务采集“正在播放的声音”
// （默认 sink / 回环设备），并以 float32 样本流投递给调用方。
//
// 安全红线：任何后端都不得退回到麦克风等输入源；采集目标只能是
// 输出回环（PulseAudio/pipewire-pulse 的 *.monitor 源、PipeWire 的
// sink monitor 端口、ALSA 的 Loopback 卡）。
//
// 每个后端在自身线程运行事件循环；SampleSink 由后端线程调用，
// 调用方负责线程安全。后端通过 active() 上报运行健康状态，供
// SpectrumCaptureWorker 做动态选择（故障降级 / 恢复切换）。
class CaptureBackend
{
public:
    using SampleSink = std::function<void(const float *, size_t)>;

    virtual ~CaptureBackend() = default;

    // 后端显示名（日志用）
    virtual const char *name() const = 0;
    // 快速探测：本系统是否存在该后端可能的采集目标（库/服务/设备）。
    // 只做廉价检查，不建立实际采集流。
    virtual bool probe() = 0;
    // 启动采集（异步连接；成功与否以 active() 为准）。失败返回 false。
    virtual bool start(SampleSink sink) = 0;
    // 停止采集并回收资源（幂等）。
    virtual void stop() = 0;
    // 采集流当前是否已连接且健康。
    virtual bool active() const = 0;
    // 最近一次失败原因（日志）。
    virtual QString lastError() const = 0;
};
