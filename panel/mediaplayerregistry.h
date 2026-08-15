// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QVariantList>

class QDBusPendingCallWatcher;
class MprisSignalRelay;

// MPRIS 播放器注册表（QML 单例 org.deepin.widgettoolbar/MediaPlayers）：
// 枚举会话总线上的 org.mpris.MediaPlayer2.* 服务，读取 Identity 供设置面板
// 与 MediaPlayer 代理使用，并跟踪最近产生播放器信号的服务作为 auto 模式候选。
class MediaPlayers : public QObject
{
    Q_OBJECT
    friend class MprisSignalRelay;
    Q_PROPERTY(QVariantList players READ players NOTIFY playersChanged)
    Q_PROPERTY(QString activeService READ activeService NOTIFY activeServiceChanged)

public:
    static MediaPlayers *instance();

    explicit MediaPlayers(QObject *parent = nullptr);
    ~MediaPlayers() override;

    QVariantList players() const;
    QString activeService() const;

    Q_INVOKABLE QString playerName(const QString &service) const;
    Q_INVOKABLE QStringList serviceNames() const;
    Q_INVOKABLE bool isRunning(const QString &service) const;

Q_SIGNALS:
    void playersChanged();
    void activeServiceChanged();

private Q_SLOTS:
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void onIdentityFetched(const QString &service, QDBusPendingCallWatcher *watcher);
    void onRegisteredServiceNames(QDBusPendingCallWatcher *watcher);

private:
    void addService(const QString &service);
    void removeService(const QString &service);
    void connectToService(const QString &service);
    void disconnectFromService(const QString &service);
    void notePlayerSignal(const QString &service);
    void setActiveService(const QString &service);

    QStringList m_services;
    QHash<QString, QString> m_names;
    QHash<QString, MprisSignalRelay *> m_relays;
    QString m_activeService;
    static MediaPlayers *s_instance;
};
