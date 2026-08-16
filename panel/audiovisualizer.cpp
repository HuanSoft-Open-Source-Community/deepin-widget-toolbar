// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "audiovisualizer.h"

#include "spectrumcapture.h"

#include <QDebug>

namespace {
// setActive 入参护栏：clientId 过长/过多直接忽略，防止恶意小组件撑爆表项
constexpr int kMaxClientIdLength = 64;
constexpr int kMaxClients = 64;
}

AudioVisualizer::AudioVisualizer(QObject *parent)
    : QObject(parent)
{
    m_worker = new SpectrumCaptureWorker(this);
    connect(m_worker, &SpectrumCaptureWorker::availableChanged,
            this, &AudioVisualizer::onWorkerAvailable);
    connect(m_worker, &SpectrumCaptureWorker::levelsReady,
            this, &AudioVisualizer::onWorkerLevels);
    // 工作线程随插件生命周期常驻，仅在有实例需求时才会真正连接音频服务
    m_worker->start();
}

AudioVisualizer::~AudioVisualizer()
{
    if (m_worker)
        m_worker->stop();
}

bool AudioVisualizer::available() const
{
    return m_available;
}

int AudioVisualizer::bandCount() const
{
    return SpectrumCaptureWorker::kBandCount;
}

QVariantList AudioVisualizer::levels() const
{
    return m_levels;
}

bool AudioVisualizer::active() const
{
    return m_active;
}

void AudioVisualizer::setActive(const QString &clientId, bool active)
{
    QString id = clientId.trimmed();
    if (id.isEmpty() || id.size() > kMaxClientIdLength)
        return;

    const bool had = m_clients.value(id, false);
    if (had == active)
        return;

    if (active) {
        if (m_clients.size() >= kMaxClients && !m_clients.contains(id)) {
            qWarning() << "AudioVisualizer: too many clients, ignoring" << id;
            return;
        }
        m_clients.insert(id, true);
    } else {
        m_clients.remove(id);
    }
    refreshActive();
}

void AudioVisualizer::onWorkerAvailable(bool available)
{
    if (m_available == available)
        return;
    m_available = available;
    Q_EMIT availableChanged();
}

void AudioVisualizer::onWorkerLevels(const QVector<int> &levels)
{
    // 复用列表避免高频分配；信号经队列连接到达主线程
    m_levels.clear();
    m_levels.reserve(levels.size());
    for (int value : levels)
        m_levels.append(value);
    Q_EMIT levelsChanged();
}

void AudioVisualizer::refreshActive()
{
    const bool next = !m_clients.isEmpty();
    if (m_active == next)
        return;
    m_active = next;
    Q_EMIT activeChanged();

    if (m_worker) {
        if (next)
            m_worker->startCapture();
        else
            m_worker->stopCapture();
    }
}
