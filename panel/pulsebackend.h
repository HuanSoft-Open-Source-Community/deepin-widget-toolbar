// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "audiobackend.h"

#include <QString>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <thread>

// PulseAudio / pipewire-pulse 采集后端：
// 以 dlopen 方式加载 libpulse.so.0，记录**默认 sink 的 monitor 源**
// （系统正在播放的音频回环）。安全红线：只接受名称以 ".monitor" 结尾的
// 源；解析失败即失败，绝不回退到麦克风等输入源。
class PulseCaptureBackend : public CaptureBackend
{
public:
    PulseCaptureBackend();
    ~PulseCaptureBackend() override;

    const char *name() const override { return "PulseAudio"; }
    bool probe() override;
    bool start(SampleSink sink) override;
    void stop() override;
    bool active() const override { return m_active.load(); }
    QString lastError() const override { return m_lastError; }

private:
    // ---- libpulse ABI（与 libpulse.so.0 对齐，避免构建依赖） ----
    struct PaSampleSpec {
        int32_t format;
        uint32_t rate;
        uint8_t channels;
    };
    struct PaServerInfo {
        const char *user_name;
        const char *host_name;
        const char *server_version;
        const char *server_name;
        PaSampleSpec sample_spec;
        const char *default_sink_name;
        const char *default_source_name;
        uint32_t cookie;
        uint8_t tail[132];
    };
    struct PaSinkInfo {
        const char *name;
        uint32_t index;
        const char *description;
        PaSampleSpec sample_spec;
        uint8_t channel_map[132];
        uint32_t owner_module;
        uint8_t cvolume[132];
        int32_t mute;
        uint32_t monitor_source;
        const char *monitor_source_name;
        uint8_t tail[160];
    };
    struct PaBufferAttr {
        uint32_t maxlength;
        uint32_t tlength;
        uint32_t prebuf;
        uint32_t minreq;
        uint32_t fragsize;
    };
    struct PulseApi {
        void *handle = nullptr;
        void *(*mainloop_new)() = nullptr;
        void *(*mainloop_get_api)(void *) = nullptr;
        int (*mainloop_iterate)(void *, int, int *) = nullptr;
        void (*mainloop_free)(void *) = nullptr;
        void *(*context_new)(void *, const char *) = nullptr;
        int (*context_connect)(void *, const char *, unsigned, void *) = nullptr;
        void (*context_set_state_callback)(void *, void (*)(void *, void *), void *) = nullptr;
        int (*context_get_state)(void *) = nullptr;
        void (*context_disconnect)(void *) = nullptr;
        void (*context_unref)(void *) = nullptr;
        void *(*context_get_server_info)(void *, void (*)(void *, const void *, void *), void *) = nullptr;
        void *(*context_get_sink_info_by_name)(void *, const char *,
                                               void (*)(void *, const void *, int, void *), void *) = nullptr;
        void (*operation_unref)(void *) = nullptr;
        void *(*stream_new)(void *, const char *, const PaSampleSpec *, void *) = nullptr;
        void (*stream_set_state_callback)(void *, void (*)(void *, void *), void *) = nullptr;
        void (*stream_set_read_callback)(void *, void (*)(void *, size_t, void *), void *) = nullptr;
        int (*stream_connect_record)(void *, const char *, const PaBufferAttr *, unsigned) = nullptr;
        int (*stream_get_state)(void *) = nullptr;
        int (*stream_peek)(void *, const void **, size_t *) = nullptr;
        int (*stream_drop)(void *) = nullptr;
        void (*stream_disconnect)(void *) = nullptr;
        void (*stream_unref)(void *) = nullptr;
    };

    enum class State { Idle, Connecting, Resolving, StreamConnecting, Ready, Failed };

    void run();
    bool loadPulse();
    void connectContext();
    void createRecordStream(const char *monitorSource);
    void teardownStream();
    void teardownContext();
    void setActiveInternal(bool active);

    static void contextStateCb(void *context, void *userdata);
    static void serverInfoCb(void *context, const void *info, void *userdata);
    static void sinkInfoCb(void *context, const void *info, int eol, void *userdata);
    static void streamStateCb(void *stream, void *userdata);
    static void streamReadCb(void *stream, size_t nbytes, void *userdata);

    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_active{false};
    SampleSink m_sink;

    PulseApi m_pulse;
    void *m_mainloop = nullptr;
    void *m_context = nullptr;
    void *m_stream = nullptr;
    State m_state = State::Idle;
    QString m_defaultSink;
    QString m_monitorSource;
    std::chrono::steady_clock::time_point m_lastRetry;
    QString m_lastError;
};
