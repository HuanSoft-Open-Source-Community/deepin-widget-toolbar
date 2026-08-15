// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantMap>

class QDBusMessage;
class QDBusPendingCallWatcher;
class QDBusServiceWatcher;

// MPRIS 播放器代理（QML 可创建类型 org.deepin.widgettoolbar/MediaPlayer）：
// 每个播放控制器小组件实例创建一个，按 mode/service 绑定目标播放器，
// 订阅播放器属性变化，向 QML 暴露曲目/封面/进度/能力，并转发控制与 seek。
class MediaPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString service READ service WRITE setService NOTIFY serviceChanged)
    Q_PROPERTY(QString activeService READ activeService NOTIFY stateChanged)
    Q_PROPERTY(QString playerName READ playerName NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY stateChanged)
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY stateChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY stateChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY stateChanged)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY stateChanged)
    Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY stateChanged)
    Q_PROPERTY(qint64 lengthMs READ lengthMs NOTIFY stateChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY stateChanged)
    Q_PROPERTY(bool canControl READ canControl NOTIFY stateChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY stateChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY stateChanged)
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY stateChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY stateChanged)

public:
    explicit MediaPlayer(QObject *parent = nullptr);

    QString mode() const;
    void setMode(const QString &mode);

    QString service() const;
    void setService(const QString &service);

    QString activeService() const;
    QString playerName() const;
    bool connected() const;
    bool hasTrack() const;
    QString playbackStatus() const;
    QString title() const;
    QString artist() const;
    QString artUrl() const;
    qint64 positionMs() const;
    qint64 lengthMs() const;
    bool canSeek() const;
    bool canControl() const;
    bool canGoNext() const;
    bool canGoPrevious() const;
    bool canPlay() const;
    bool canPause() const;

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qint64 ms);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void modeChanged();
    void serviceChanged();
    void stateChanged();

private Q_SLOTS:
    void onPropertiesChanged(const QDBusMessage &message);
    void onSeeked(const QDBusMessage &message);
    void onServiceRegistered(const QString &service);
    void onServiceUnregistered(const QString &service);
    void onPlayersChanged();
    void onStateFetched(QDBusPendingCallWatcher *watcher);

private:
    void selectTarget();
    void connectToService(const QString &service);
    void fetchState();
    void applyProperties(const QVariantMap &props);
    void parseMetadata(const QVariant &metadata);
    void resetState();
    void updatePosition();
    void startPositionTimerIfNeeded();

    QString m_mode = QStringLiteral("auto");
    QString m_service;
    QString m_activeService;
    QDBusServiceWatcher *m_watcher = nullptr;

    bool m_connected = false;
    bool m_hasTrack = false;
    QString m_playbackStatus;
    QString m_title;
    QString m_artist;
    QString m_artUrl;
    QString m_trackId;
    bool m_fetchFailed = false;
    qint64 m_positionMs = 0;
    qint64 m_lengthMs = 0;
    qint64 m_positionBaseMs = 0;
    qint64 m_positionBaseEpochMs = 0;
    double m_rate = 1.0;

    bool m_canSeek = false;
    bool m_canControl = false;
    bool m_canGoNext = false;
    bool m_canGoPrevious = false;
    bool m_canPlay = false;
    bool m_canPause = false;

    QTimer m_positionTimer;
};
