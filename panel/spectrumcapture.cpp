// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "spectrumcapture.h"

#include "alsabackend.h"
#include "audiobackend.h"
#include "fft.h"
#include "pipewirebackend.h"
#include "pulsebackend.h"

#include <QDebug>

#include <cmath>

namespace {
constexpr double kPi = 3.14159265358979323846;

int64_t nowMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
} // namespace

SpectrumCaptureWorker::SpectrumCaptureWorker(QObject *parent)
    : QObject(parent)
{
    // 优先级顺序：PulseAudio 覆盖纯 Pulse 与 pipewire-pulse 系统；
    // PipeWire 原生用于无 pipewire-pulse 的系统；ALSA 仅回环设备兜底。
    m_backends.push_back(std::make_unique<PulseCaptureBackend>());
    m_backends.push_back(std::make_unique<PipeWireCaptureBackend>());
    m_backends.push_back(std::make_unique<AlsaCaptureBackend>());
}

SpectrumCaptureWorker::~SpectrumCaptureWorker()
{
    stop();
}

bool SpectrumCaptureWorker::start()
{
    if (m_running.load())
        return true;
    m_stop.store(false);
    m_thread = std::thread([this]() { runLoop(); });
    m_running.store(true);
    return true;
}

void SpectrumCaptureWorker::stop()
{
    if (!m_running.load())
        return;
    m_stop.store(true);
    notifyLoop();
    if (m_thread.joinable())
        m_thread.join();
    m_running.store(false);
}

void SpectrumCaptureWorker::startCapture()
{
    if (m_captureWanted.load())
        return;
    m_captureWanted.store(true);
    notifyLoop();
}

void SpectrumCaptureWorker::stopCapture()
{
    if (!m_captureWanted.load())
        return;
    m_captureWanted.store(false);
    notifyLoop();
}

void SpectrumCaptureWorker::notifyLoop()
{
    std::lock_guard<std::mutex> lock(m_cvMutex);
    m_cv.notify_all();
}

bool SpectrumCaptureWorker::waitForWork(int state)
{
    std::unique_lock<std::mutex> lock(m_cvMutex);
    if (state == 0) {
        // 未请求采集：无限等待，直到 startCapture（wanted=true）或 stop
        // 经 notifyLoop() 唤醒，线程 CPU≈0。
        m_cv.wait(lock, [this]() {
            return m_stop.load() || m_captureWanted.load();
        });
        return !m_stop.load();
    }

    // 请求中：按状态节流（10ms 活跃节拍 / 250ms 重试间隔）。
    // 注意：带谓词的 wait_for 在谓词已为真时会立即返回，活跃采集期间
    // wanted 恒为真，故此处谓词只用 stop，保证定时等待真正等满时长，
    // 避免把 10ms 节拍退化成忙自旋；stop() 经 notify 立即唤醒。
    const auto pred = [this]() { return m_stop.load(); };
    if (state == 1)
        m_cv.wait_for(lock, std::chrono::milliseconds(250), pred);
    else
        m_cv.wait_for(lock, std::chrono::milliseconds(10), pred);
    return !m_stop.load();
}

void SpectrumCaptureWorker::runLoop()
{
    m_lastAnalyze = std::chrono::steady_clock::now();
    m_lastReselect = std::chrono::steady_clock::now();
    m_lastSelectAttempt = std::chrono::steady_clock::time_point{};
    m_lastDataMs.store(nowMs());
    bool wasWanted = false;

    while (!m_stop.load()) {
        const bool wanted = m_captureWanted.load();
        if (wanted != wasWanted) {
            wasWanted = wanted;
            if (wanted) {
                m_lastSelectAttempt = std::chrono::steady_clock::time_point{};
            } else if (m_current) {
                m_current->stop();
                m_current = nullptr;
                m_backendIndex = -1;
                setAvailable(false);
            }
        }

        // 空闲（未请求采集）时无限等待：线程 CPU≈0；
        // 请求中无后端时 250ms 节流重试；采集活跃时 10ms 节拍。
        int state;
        if (!wanted) {
            state = 0;
        } else if (m_current && m_current->active()) {
            state = 2;
            if (!m_available)
                setAvailable(true);
            maybeReselect();
            analyzeTick();
        } else {
            state = 1;
            const auto now = std::chrono::steady_clock::now();
            if (m_current) {
                // 连接中或已失败：宽限期后判定失败并切换到下一后端
                const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - m_currentSince).count();
                if (elapsed > kConnectGraceMs) {
                    qWarning() << "SpectrumCapture: backend" << m_current->name()
                               << "failed:" << m_current->lastError();
                    m_current->stop();
                    m_current = nullptr;
                    setAvailable(false);
                }
            } else {
                // 无当前后端：按重试间隔尝试下一个候选
                const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - m_lastSelectAttempt).count();
                if (elapsed >= kReselectIntervalMs) {
                    m_lastSelectAttempt = now;
                    selectBackend();
                }
            }
        }

        if (!waitForWork(state))
            break;
    }

    if (m_current) {
        m_current->stop();
        m_current = nullptr;
    }
    m_backendIndex = -1;
    setAvailable(false);
}

void SpectrumCaptureWorker::selectBackend()
{
    if (m_current)
        return;
    const int n = static_cast<int>(m_backends.size());
    for (int i = 0; i < n; ++i) {
        const int idx = (m_backendIndex + 1 + i) % n;
        if (!m_backends[idx]->probe())
            continue;
        m_backendIndex = idx;
        m_backends[idx]->start([this](const float *data, size_t count) {
            handleSamples(data, count);
        });
        m_current = m_backends[idx].get();
        m_currentSince = std::chrono::steady_clock::now();
        return;
    }
    m_backendIndex = -1;
}

void SpectrumCaptureWorker::maybeReselect()
{
    // 当前后端工作正常时，周期性检查更高优先级的后端是否已可用并切回
    const auto now = std::chrono::steady_clock::now();
    if (std::chrono::duration_cast<std::chrono::milliseconds>(
            now - m_lastReselect).count() < kReselectIntervalMs)
        return;
    m_lastReselect = now;

    for (int i = 0; i < m_backendIndex; ++i) {
        if (m_backends[i]->probe()) {
            qInfo() << "SpectrumCapture: switching to higher-priority backend"
                    << m_backends[i]->name();
            m_current->stop();
            m_current = nullptr;
            setAvailable(false);
            m_lastSelectAttempt = std::chrono::steady_clock::time_point{};
            return;
        }
    }
}

void SpectrumCaptureWorker::handleSamples(const float *data, size_t count)
{
    if (!data || count == 0)
        return;
    m_lastDataMs.store(nowMs());
    std::lock_guard<std::mutex> lock(m_ringMutex);
    pushRing(data, count);
}

void SpectrumCaptureWorker::pushRing(const float *data, size_t count)
{
    const size_t keep = count > kRingCapacity ? kRingCapacity : count;
    const size_t offset = count - keep;
    for (size_t i = 0; i < keep; ++i) {
        m_ring[m_ringHead] = data[offset + i];
        m_ringHead = (m_ringHead + 1) % kRingCapacity;
    }
    m_ringCount = keep >= static_cast<size_t>(kRingCapacity)
        ? kRingCapacity : m_ringCount + static_cast<int>(keep);
    if (m_ringCount > kRingCapacity)
        m_ringCount = kRingCapacity;
}

void SpectrumCaptureWorker::analyzeTick()
{
    const auto now = std::chrono::steady_clock::now();
    if (std::chrono::duration_cast<std::chrono::milliseconds>(
            now - m_lastAnalyze).count() < kAnalyzeIntervalMs)
        return;
    m_lastAnalyze = now;

    // 超过静音阈值按静音处理：喂零输入让柱体经释放平滑自然回落
    const bool silent = nowMs() - m_lastDataMs.load() > kSilenceTimeoutMs;

    if (!m_analysisInited) {
        for (int i = 0; i < kAnalysisSize; ++i)
            m_window[i] = 0.5 - 0.5 * std::cos((2.0 * kPi * i) / (kAnalysisSize - 1));
        m_analysisInited = true;
    }

    // 在锁内拷贝最近 128 个样本，锁外做 FFT
    double mono[kAnalysisSize] = {0.0};
    {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        if (!silent && m_ringCount >= kAnalysisSize) {
            const int start = (m_ringHead - kAnalysisSize + kRingCapacity) % kRingCapacity;
            for (int i = 0; i < kAnalysisSize; ++i) {
                const int idx = (start + i) % kRingCapacity;
                mono[i] = m_ring[idx] * m_window[i];
            }
        }
    }

    // 128 点 radix-2 FFT（C 风格模块 wsf，twiddle 预计算，热点零三角函数），
    // 输出与旧朴素 DFT 逐 bin 数值等价（无 1/N 归一化，同尺度）。
    constexpr int kUsefulBins = kAnalysisSize / 2;
    double magnitudes[kUsefulBins] = {0.0};
    wsf::realMagnitudes(mono, kAnalysisSize, magnitudes + 1, kUsefulBins - 1);
    for (int bin = 1; bin < kUsefulBins; ++bin) {
        const double emphasis = 1.0 + (static_cast<double>(bin) / (kUsefulBins - 1)) * 0.35;
        magnitudes[bin] = magnitudes[bin] / (kAnalysisSize / 2.0) * emphasis;
    }

    // 分组 32 带：每带取峰值幅度，log 压缩到 0..100，攻击/释放平滑
    for (int i = 0; i < kBandCount; ++i) {
        int startBin = 1 + (i * (kUsefulBins - 1)) / kBandCount;
        int endBin = 1 + ((i + 1) * (kUsefulBins - 1)) / kBandCount;
        if (endBin <= startBin)
            endBin = startBin + 1;
        if (endBin > kUsefulBins)
            endBin = kUsefulBins;

        double bandEnergy = 0.0;
        for (int bin = startBin; bin < endBin; ++bin) {
            if (magnitudes[bin] > bandEnergy)
                bandEnergy = magnitudes[bin];
        }

        double compressed = std::log1p(bandEnergy * 48.0) / std::log1p(49.0);
        double scaled = compressed * 100.0;
        if (scaled < 0.0)
            scaled = 0.0;
        if (scaled > 100.0)
            scaled = 100.0;

        double &prev = m_levels[i];
        if (scaled > prev)
            prev = (prev + scaled * 3.0) / 4.0;   // 攻击：快速上升
        else
            prev = (prev * 3.0 + scaled) / 4.0;   // 释放：缓慢回落
        if (prev < 1.0)
            prev = 0.0;

        double &peak = m_peaks[i];
        if (prev > peak)
            peak = prev;
        else if (peak > 0.0)
            peak -= 1.0;
    }

    // 发射节流：32 带整型值未变化时跳过，避免静音场景下 30Hz 无谓信号
    bool levelsChanged = false;
    for (int i = 0; i < kBandCount; ++i) {
        const int level = static_cast<int>(qBound(0.0, m_levels[i], 100.0));
        if (level != m_lastLevels[i]) {
            levelsChanged = true;
            break;
        }
    }
    if (!levelsChanged)
        return;

    QVector<int> levels;
    levels.reserve(kBandCount);
    for (int i = 0; i < kBandCount; ++i) {
        const int level = static_cast<int>(qBound(0.0, m_levels[i], 100.0));
        levels.append(level);
        m_lastLevels[i] = level;
    }
    Q_EMIT levelsReady(levels);
}

void SpectrumCaptureWorker::setAvailable(bool available)
{
    if (m_available == available)
        return;
    m_available = available;
    Q_EMIT availableChanged(available);
}