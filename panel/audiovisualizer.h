// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QVariantList>

class SpectrumCaptureWorker;

// 系统音频频谱能力代理（QML 单例 org.deepin.widgettoolbar/AudioVisualizer）：
// 小组件不允许直接访问音频服务，频谱数据统一经本代理获取。
//
// 安全边界：
//   - 仅暴露只读数值接口（available / bandCount / levels / active），
//     小组件拿不到原始 PCM，也没有任何写入口；
//   - 采集仅默认 sink 的 monitor 源（输出回环，非麦克风），由内部
//     SpectrumCaptureWorker 在独立线程完成；
//   - setActive 按 clientId 引用计数：全部实例释放后立即停止采集。
class AudioVisualizer : public QObject
{
    Q_OBJECT
    // 采集流是否就绪（可捕获系统音频）
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // 频谱带数（固定 32）
    Q_PROPERTY(int bandCount READ bandCount CONSTANT)
    // 最近一帧频谱快照（32 个 0..100 整数，约 30Hz 更新）
    Q_PROPERTY(QVariantList levels READ levels NOTIFY levelsChanged)
    // 是否有实例正在采集（任一侧栏实例可见且面板可见）
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit AudioVisualizer(QObject *parent = nullptr);
    ~AudioVisualizer() override;

    bool available() const;
    int bandCount() const;
    QVariantList levels() const;
    bool active() const;

    // 实例注册/注销采集需求（clientId 通常为实例 UUID）
    Q_INVOKABLE void setActive(const QString &clientId, bool active);

Q_SIGNALS:
    void availableChanged();
    void levelsChanged();
    void activeChanged();

private Q_SLOTS:
    void onWorkerAvailable(bool available);
    void onWorkerLevels(const QVector<int> &levels);

private:
    void refreshActive();

    SpectrumCaptureWorker *m_worker = nullptr;
    QHash<QString, bool> m_clients;
    QVariantList m_levels;
    bool m_available = false;
    bool m_active = false;
};
