// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "alsabackend.h"

#include <QDebug>
#include <QFile>
#include <QStringList>

#include <chrono>
#include <cstring>
#include <dlfcn.h>

namespace {

constexpr char kAlsaSoname[] = "libasound.so.2";

// snd_pcm_stream_t
constexpr int kPcmStreamCapture = 1;
// snd_pcm_format_t
constexpr int kFormatS16Le = 2;
// snd_pcm_state_t
constexpr int kPcmStateRunning = 3;
constexpr int kPcmStatePrepared = 4;

constexpr unsigned kSampleRate = 48000;

// 只尝试回环设备名；绝不回退到默认设备
const char *const kLoopbackCandidates[] = {
    "hw:Loopback,0,1",
    "plughw:Loopback,0,1",
    "Loopback",
};

#define LOAD_SYMBOL(api, handle, name)     do {         *(void **)(&(api).name) = dlsym(handle, "snd_" #name);         if (!(api).name) {             qWarning() << "AlsaCaptureBackend: dlsym snd_" #name " failed:" << dlerror();             return false;         }     } while (0)

} // namespace

AlsaCaptureBackend::AlsaCaptureBackend()
{
}

AlsaCaptureBackend::~AlsaCaptureBackend()
{
    stop();
}

bool AlsaCaptureBackend::probe()
{
    // 先查动态库，再查是否有 Loopback 卡；找到的设备名存入 m_device
    if (!loadAlsa())
        return false;
    m_device.clear();
    return findLoopbackDevice(&m_device);
}

bool AlsaCaptureBackend::start(SampleSink sink)
{
    if (m_running.load())
        return true;
    m_sink = std::move(sink);
    m_stop.store(false);
    m_thread = std::thread([this]() { run(); });
    m_running.store(true);
    return true;
}

void AlsaCaptureBackend::stop()
{
    if (!m_running.load())
        return;
    m_stop.store(true);
    if (m_pcm) {
        // snd_pcm_close 会中止阻塞中的 readi；从其它线程调用是允许的
        m_alsa.pcm_close(m_pcm);
        m_pcm = nullptr;
    }
    if (m_thread.joinable())
        m_thread.join();
    m_running.store(false);
    m_sink = nullptr;
}

bool AlsaCaptureBackend::loadAlsa()
{
    if (m_alsa.handle)
        return true;
    void *handle = dlopen(kAlsaSoname, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        m_lastError = QStringLiteral("dlopen libasound.so.2 failed");
        return false;
    }
    m_alsa.handle = handle;
    LOAD_SYMBOL(m_alsa, handle, pcm_open);
    LOAD_SYMBOL(m_alsa, handle, pcm_set_params);
    LOAD_SYMBOL(m_alsa, handle, pcm_readi);
    LOAD_SYMBOL(m_alsa, handle, pcm_state);
    LOAD_SYMBOL(m_alsa, handle, pcm_close);
    LOAD_SYMBOL(m_alsa, handle, strerror);
    return true;
}

bool AlsaCaptureBackend::findLoopbackDevice(QString *device) const
{
    // /proc/asound/cards 中必须存在 Loopback 卡（snd-aloop），否则不可用
    QFile cards(QStringLiteral("/proc/asound/cards"));
    if (!cards.open(QIODevice::ReadOnly))
        return false;
    const QByteArray content = cards.readAll();
    if (!content.contains("Loopback"))
        return false;
    // 尝试打开回环捕获设备（有 Loopback 卡时第一个候选通常可用）
    for (const char *candidate : kLoopbackCandidates) {
        void *pcm = nullptr;
        if (m_alsa.pcm_open(&pcm, candidate, kPcmStreamCapture, 0) == 0) {
            if (device)
                *device = QString::fromUtf8(candidate);
            if (pcm)
                m_alsa.pcm_close(pcm);
            return true;
        }
    }
    return false;
}

void AlsaCaptureBackend::run()
{
    if (!probe()) {
        setActiveInternal(false);
        return;
    }
    // probe 已确认设备可打开；再次打开用于持续采集
    if (m_alsa.pcm_open(&m_pcm, qPrintable(m_device), kPcmStreamCapture, 0) < 0) {
        m_lastError = QStringLiteral("snd_pcm_open failed");
        setActiveInternal(false);
        return;
    }
    // S16LE 单声道 48kHz，非阻塞(500)打开即中断后可恢复
    if (m_alsa.pcm_set_params(m_pcm, kFormatS16Le, 1, kSampleRate, 1, 50000) < 0) {
        m_lastError = QStringLiteral("snd_pcm_set_params failed");
        m_alsa.pcm_close(m_pcm);
        m_pcm = nullptr;
        setActiveInternal(false);
        return;
    }

    m_active.store(true);
    constexpr int kFrames = 1024;
    int16_t buffer[kFrames * 2] = {0};
    float mono[kFrames] = {0.0f};
    while (!m_stop.load()) {
        const long frames = m_alsa.pcm_readi(m_pcm, buffer,
                                             static_cast<unsigned long>(kFrames));
        if (frames < 0) {
            // 设备被暂停/恢复（回环在无输出时可能暂停）：短暂重试
            if (!m_stop.load())
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            continue;
        }
        if (frames == 0)
            continue;
        const long n = frames > kFrames ? kFrames : frames;
        for (long i = 0; i < n; ++i)
            mono[i] = static_cast<float>(buffer[i]) / 32768.0f;
        if (m_sink)
            m_sink(mono, static_cast<size_t>(n));
    }

    if (m_pcm) {
        m_alsa.pcm_close(m_pcm);
        m_pcm = nullptr;
    }
    if (m_alsa.handle) {
        dlclose(m_alsa.handle);
        m_alsa.handle = nullptr;
    }
    setActiveInternal(false);
}

void AlsaCaptureBackend::setActiveInternal(bool active)
{
    m_active.store(active);
}
