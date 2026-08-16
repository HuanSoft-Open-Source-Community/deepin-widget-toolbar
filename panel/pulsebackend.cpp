// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pulsebackend.h"

#include <QDebug>

#include <cmath>
#include <cstring>
#include <dlfcn.h>

namespace {

constexpr char kPulseSoname[] = "libpulse.so.0";

// pa_context_state
constexpr int kCtxReady = 4;
constexpr int kCtxFailed = 5;
constexpr int kCtxTerminated = 6;

// pa_stream_state
constexpr int kStreamReady = 2;
constexpr int kStreamFailed = 3;
constexpr int kStreamTerminated = 4;

// pa_sample_format
constexpr int kSampleFloat32Le = 5;

// pa_stream_flags
constexpr unsigned kStreamNoFlags = 0x0000U;
constexpr unsigned kStreamAdjustLatency = 0x2000U;

constexpr unsigned kContextNoFlags = 0U;

bool endsWithMonitorSuffix(const char *name)
{
    if (!name)
        return false;
    const size_t len = std::strlen(name);
    return len >= 8 && std::strcmp(name + len - 8, ".monitor") == 0;
}

// 采集缓冲：显式设置较小的 fragsize。pipewire-pulse 对 record 流默认以
// 64KB（约 341ms）大块投递 monitor 数据，投递间隔会超过调用方的静音
// 判定阈值导致频谱被误判为静音；8192 字节 ≈ 43ms/块，数据持续流动。
constexpr uint32_t kMaxLength = 32768;
constexpr uint32_t kFragSize = 8192;

#define LOAD_SYMBOL(api, handle, name)     do {         *(void **)(&(api).name) = dlsym(handle, "pa_" #name);         if (!(api).name) {             qWarning() << "PulseCaptureBackend: dlsym pa_" #name " failed:" << dlerror();             return false;         }     } while (0)

} // namespace

PulseCaptureBackend::PulseCaptureBackend()
{
}

PulseCaptureBackend::~PulseCaptureBackend()
{
    stop();
}

bool PulseCaptureBackend::probe()
{
    // 只检查动态库可加载；服务器可达性由 start() 的实际连接决定
    return loadPulse();
}

bool PulseCaptureBackend::start(SampleSink sink)
{
    if (m_running.load())
        return true;
    m_sink = std::move(sink);
    m_stop.store(false);
    m_thread = std::thread([this]() { run(); });
    m_running.store(true);
    return true;
}

void PulseCaptureBackend::stop()
{
    if (!m_running.load())
        return;
    m_stop.store(true);
    if (m_thread.joinable())
        m_thread.join();
    m_running.store(false);
    m_sink = nullptr;
}

void PulseCaptureBackend::run()
{
    m_lastRetry = std::chrono::steady_clock::now();
    bool started = false;

    while (!m_stop.load()) {
        if (m_mainloop && m_pulse.mainloop_iterate)
            m_pulse.mainloop_iterate(m_mainloop, 50, nullptr);
        if (m_stop.load())
            break;

        if (!started && loadPulse()) {
            started = true;
            connectContext();
        }
        if (started && (m_state == State::Failed || m_state == State::Idle)) {
            const auto now = std::chrono::steady_clock::now();
            if (std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - m_lastRetry).count() >= 5000) {
                m_lastRetry = now;
                connectContext();
            }
        }
    }

    teardownStream();
    teardownContext();
    if (m_pulse.handle) {
        dlclose(m_pulse.handle);
        m_pulse.handle = nullptr;
    }
    m_state = State::Idle;
    setActiveInternal(false);
}

bool PulseCaptureBackend::loadPulse()
{
    if (m_pulse.handle)
        return true;
    void *handle = dlopen(kPulseSoname, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        m_lastError = QStringLiteral("dlopen libpulse.so.0 failed");
        return false;
    }
    m_pulse.handle = handle;
    LOAD_SYMBOL(m_pulse, handle, mainloop_new);
    LOAD_SYMBOL(m_pulse, handle, mainloop_get_api);
    LOAD_SYMBOL(m_pulse, handle, mainloop_iterate);
    LOAD_SYMBOL(m_pulse, handle, mainloop_free);
    LOAD_SYMBOL(m_pulse, handle, context_new);
    LOAD_SYMBOL(m_pulse, handle, context_connect);
    LOAD_SYMBOL(m_pulse, handle, context_set_state_callback);
    LOAD_SYMBOL(m_pulse, handle, context_get_state);
    LOAD_SYMBOL(m_pulse, handle, context_disconnect);
    LOAD_SYMBOL(m_pulse, handle, context_unref);
    LOAD_SYMBOL(m_pulse, handle, context_get_server_info);
    LOAD_SYMBOL(m_pulse, handle, context_get_sink_info_by_name);
    LOAD_SYMBOL(m_pulse, handle, operation_unref);
    LOAD_SYMBOL(m_pulse, handle, stream_new);
    LOAD_SYMBOL(m_pulse, handle, stream_set_state_callback);
    LOAD_SYMBOL(m_pulse, handle, stream_set_read_callback);
    LOAD_SYMBOL(m_pulse, handle, stream_connect_record);
    LOAD_SYMBOL(m_pulse, handle, stream_get_state);
    LOAD_SYMBOL(m_pulse, handle, stream_peek);
    LOAD_SYMBOL(m_pulse, handle, stream_drop);
    LOAD_SYMBOL(m_pulse, handle, stream_disconnect);
    LOAD_SYMBOL(m_pulse, handle, stream_unref);
    return true;
}

void PulseCaptureBackend::connectContext()
{
    if (m_context) {
        m_pulse.context_disconnect(m_context);
        m_pulse.context_unref(m_context);
        m_context = nullptr;
    }
    if (!m_mainloop) {
        m_mainloop = m_pulse.mainloop_new();
        if (!m_mainloop) {
            m_state = State::Failed;
            m_lastError = QStringLiteral("pa_mainloop_new failed");
            return;
        }
    }
    void *api = m_pulse.mainloop_get_api(m_mainloop);
    m_context = m_pulse.context_new(api, "ds-widget-toolbar-spectrum");
    if (!m_context) {
        m_state = State::Failed;
        m_lastError = QStringLiteral("pa_context_new failed");
        return;
    }
    m_pulse.context_set_state_callback(m_context, &PulseCaptureBackend::contextStateCb, this);
    m_state = State::Connecting;
    m_defaultSink.clear();
    m_monitorSource.clear();
    if (m_pulse.context_connect(m_context, nullptr, kContextNoFlags, nullptr) < 0) {
        m_state = State::Failed;
        m_lastError = QStringLiteral("pa_context_connect failed");
    }
}

void PulseCaptureBackend::contextStateCb(void *context, void *userdata)
{
    auto *self = static_cast<PulseCaptureBackend *>(userdata);
    if (!self || context != self->m_context || !self->m_pulse.context_get_state)
        return;
    const int state = self->m_pulse.context_get_state(context);
    switch (state) {
    case kCtxReady:
        self->m_state = State::Resolving;
        if (self->m_pulse.context_get_server_info) {
            void *op = self->m_pulse.context_get_server_info(
                context, &PulseCaptureBackend::serverInfoCb, self);
            if (op && self->m_pulse.operation_unref)
                self->m_pulse.operation_unref(op);
        }
        break;
    case kCtxFailed:
    case kCtxTerminated:
        self->teardownStream();
        self->setActiveInternal(false);
        self->m_state = State::Failed;
        self->m_lastError = QStringLiteral("pulse context failed");
        break;
    default:
        break;
    }
}

void PulseCaptureBackend::serverInfoCb(void *context, const void *info, void *userdata)
{
    auto *self = static_cast<PulseCaptureBackend *>(userdata);
    if (!self || !info)
        return;
    const auto *server = static_cast<const PaServerInfo *>(info);
    self->m_defaultSink = QString::fromUtf8(server->default_sink_name
                                                ? server->default_sink_name : "");
    if (self->m_defaultSink.isEmpty()) {
        self->m_state = State::Failed;
        self->m_lastError = QStringLiteral("no default sink");
        return;
    }
    void *op = self->m_pulse.context_get_sink_info_by_name(
        context, server->default_sink_name, &PulseCaptureBackend::sinkInfoCb, self);
    if (op && self->m_pulse.operation_unref)
        self->m_pulse.operation_unref(op);
}

void PulseCaptureBackend::sinkInfoCb(void *context, const void *info, int eol, void *userdata)
{
    auto *self = static_cast<PulseCaptureBackend *>(userdata);
    if (!self || eol)
        return;
    const auto *sink = static_cast<const PaSinkInfo *>(info);
    const char *monitor = sink ? sink->monitor_source_name : nullptr;
    // 安全红线：只接受 monitor 源（默认 sink 的输出回环），
    // 名称不合规（如误拿到 alsa_input.*）一律视为失败，绝不降级到输入源。
    if (!endsWithMonitorSuffix(monitor)) {
        self->m_state = State::Failed;
        self->m_lastError = QStringLiteral("sink has no valid monitor source");
        return;
    }
    self->m_monitorSource = QString::fromUtf8(monitor);
    self->createRecordStream(monitor);
}

void PulseCaptureBackend::createRecordStream(const char *monitorSource)
{
    teardownStream();

    PaSampleSpec spec;
    spec.format = kSampleFloat32Le;
    spec.rate = 48000;
    spec.channels = 1;

    m_stream = m_pulse.stream_new(m_context, "spectrum-monitor", &spec, nullptr);
    if (!m_stream) {
        m_state = State::Failed;
        m_lastError = QStringLiteral("pa_stream_new failed");
        return;
    }
    m_pulse.stream_set_state_callback(m_stream, &PulseCaptureBackend::streamStateCb, this);
    m_pulse.stream_set_read_callback(m_stream, &PulseCaptureBackend::streamReadCb, this);

    PaBufferAttr attr;
    attr.maxlength = kMaxLength;
    attr.tlength = 0;
    attr.prebuf = 0;
    attr.minreq = 0;
    attr.fragsize = kFragSize;

    m_state = State::StreamConnecting;
    if (m_pulse.stream_connect_record(m_stream, monitorSource, &attr,
                                      kStreamNoFlags | kStreamAdjustLatency) < 0) {
        m_state = State::Failed;
        m_lastError = QStringLiteral("stream_connect_record failed");
        teardownStream();
    }
}

void PulseCaptureBackend::streamStateCb(void *stream, void *userdata)
{
    auto *self = static_cast<PulseCaptureBackend *>(userdata);
    if (!self || stream != self->m_stream || !self->m_pulse.stream_get_state)
        return;
    const int state = self->m_pulse.stream_get_state(stream);
    switch (state) {
    case kStreamReady:
        self->m_state = State::Ready;
        self->setActiveInternal(true);
        break;
    case kStreamFailed:
    case kStreamTerminated:
        self->teardownStream();
        self->setActiveInternal(false);
        self->m_state = State::Failed;
        self->m_lastError = QStringLiteral("pulse stream failed");
        break;
    default:
        break;
    }
}

void PulseCaptureBackend::streamReadCb(void *stream, size_t nbytes, void *userdata)
{
    auto *self = static_cast<PulseCaptureBackend *>(userdata);
    if (!self || stream != self->m_stream || !self->m_pulse.stream_peek
        || !self->m_pulse.stream_drop)
        return;

    const void *data = nullptr;
    size_t bytes = nbytes;
    if (self->m_pulse.stream_peek(stream, &data, &bytes) < 0) {
        self->m_pulse.stream_drop(stream);
        return;
    }
    if (data && bytes > 0 && self->m_sink)
        self->m_sink(static_cast<const float *>(data), bytes / sizeof(float));
    self->m_pulse.stream_drop(stream);
}

void PulseCaptureBackend::teardownStream()
{
    if (m_stream) {
        m_pulse.stream_disconnect(m_stream);
        m_pulse.stream_unref(m_stream);
        m_stream = nullptr;
    }
    m_state = State::Idle;
}

void PulseCaptureBackend::teardownContext()
{
    if (m_context) {
        m_pulse.context_disconnect(m_context);
        m_pulse.context_unref(m_context);
        m_context = nullptr;
    }
    if (m_mainloop) {
        m_pulse.mainloop_free(m_mainloop);
        m_mainloop = nullptr;
    }
}

void PulseCaptureBackend::setActiveInternal(bool active)
{
    m_active.store(active);
}
