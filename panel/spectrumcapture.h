// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QVector>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

class CaptureBackend;

// 系统音频频谱采集工作对象（宿主能力代理的内部实现，QML 不可见）。
//
// 多后端动态选择：PulseAudio（默认 sink monitor）→ PipeWire（sink
// monitor 端口）→ ALSA（仅 Loopback 卡），按可用性与运行状态动态降级
// /恢复；任何后端都不触碰麦克风等输入源。
//
// 结构：本对象在工作线程维护后端选择与 FFT 分析；后端各自在独立线程
// 采集，经 handleSamples() 投递 float32 样本到共享环形缓冲（互斥锁保护）。
class SpectrumCaptureWorker : public QObject
{
    Q_OBJECT
public:
    static constexpr int kBandCount = 32;
    // FFT 窗口点数（与 ter-music 一致，128 点足够视觉化且开销极小）
    static constexpr int kAnalysisSize = 128;
    // 环形缓冲容量（约 170ms @48kHz 单声道 float）
    static constexpr int kRingCapacity = 8192;
    // 分析节流：约 30 帧/秒
    static constexpr int kAnalyzeIntervalMs = 33;
    // 超过该时长无新数据即按静音处理（暂停/停播时柱体回落）
    static constexpr int kSilenceTimeoutMs = 200;
    // 后端连接宽限期（异步连接，超过仍未 active 视为失败并切换）
    static constexpr int kConnectGraceMs = 3000;
    // 后端重选 / 重试间隔
    static constexpr int kReselectIntervalMs = 5000;

    explicit SpectrumCaptureWorker(QObject *parent = nullptr);
    ~SpectrumCaptureWorker() override;

    bool start();
    void stop();

public Q_SLOTS:
    void startCapture();
    void stopCapture();

Q_SIGNALS:
    // 采集流是否就绪（可捕获系统音频）；仅在状态翻转时发出
    void availableChanged(bool available);
    // 32 带 0..100 频谱快照（约 30Hz，仅采集运行时发出）
    void levelsReady(QVector<int> levels);

private:
    void runLoop();
    // 条件变量等待辅助：返回是否因 stop 退出循环。
    // state: 0=未请求采集（无限等待）, 1=请求中无活跃后端（节流重试）, 2=采集活跃
    bool waitForWork(int state);
    void notifyLoop();
    void selectBackend();
    void maybeReselect();
    void handleSamples(const float *data, size_t count);
    void pushRing(const float *data, size_t count);
    void analyzeTick();
    void setAvailable(bool available);

    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_captureWanted{false};

    // 循环唤醒：未请求采集时线程休眠在条件变量上（CPU≈0），
    // startCapture/stopCapture/stop 经 notifyLoop() 唤醒。
    std::mutex m_cvMutex;
    std::condition_variable m_cv;

    // ---- 后端选择状态 ----
    std::vector<std::unique_ptr<CaptureBackend>> m_backends;
    CaptureBackend *m_current = nullptr;
    int m_backendIndex = -1;
    std::chrono::steady_clock::time_point m_currentSince;
    std::chrono::steady_clock::time_point m_lastSelectAttempt;
    std::chrono::steady_clock::time_point m_lastReselect;
    std::chrono::steady_clock::time_point m_lastAnalyze;

    // ---- 环形缓冲（后端线程写 / 分析线程读，互斥锁保护） ----
    std::mutex m_ringMutex;
    float m_ring[kRingCapacity] = {0.0f};
    int m_ringHead = 0;
    int m_ringCount = 0;
    std::atomic<int64_t> m_lastDataMs{0};

    // ---- 分析状态 ----
    double m_levels[kBandCount] = {0.0};
    double m_peaks[kBandCount] = {0.0};
    // 上次发射的整型带值（发射节流用；静音首帧全 0 跳过发射无妨，
    // 空闲呼吸动画由 QML 侧自身定时器驱动，不依赖 levels 信号）
    int m_lastLevels[kBandCount] = {0};
    bool m_analysisInited = false;
    double m_window[kAnalysisSize] = {0.0};
    bool m_available = false;
};
