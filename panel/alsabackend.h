// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "audiobackend.h"

#include <QString>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <thread>

// ALSA 采集后端（仅回环设备）：
// ALSA 无法直接采集系统输出，只有加载了 snd-aloop（出现 "Loopback" 卡）
// 的系统才能用它采集“正在播放的声音”。安全红线：probe() 只在检测到
// Loopback 卡时返回 true，且只打开名称含 "Loopback" 的捕获设备，
// 绝不打开默认捕获设备（那是麦克风）。
class AlsaCaptureBackend : public CaptureBackend
{
public:
    AlsaCaptureBackend();
    ~AlsaCaptureBackend() override;

    const char *name() const override { return "ALSA"; }
    bool probe() override;
    bool start(SampleSink sink) override;
    void stop() override;
    bool active() const override { return m_active.load(); }
    QString lastError() const override { return m_lastError; }

private:
    void run();
    void setActiveInternal(bool active);

    struct AlsaApi {
        void *handle = nullptr;
        int (*pcm_open)(void **, const char *, int, int) = nullptr;
        int (*pcm_set_params)(void *, unsigned, int, int, unsigned, unsigned) = nullptr;
        long (*pcm_readi)(void *, void *, unsigned long) = nullptr;
        int (*pcm_state)(void *) = nullptr;
        int (*pcm_close)(void *) = nullptr;
        const char *(*strerror)(int) = nullptr;
    };

    bool loadAlsa();
    bool findLoopbackDevice(QString *device) const;

    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_active{false};
    SampleSink m_sink;
    AlsaApi m_alsa;
    void *m_pcm = nullptr;
    QString m_device;
    QString m_lastError;
};
