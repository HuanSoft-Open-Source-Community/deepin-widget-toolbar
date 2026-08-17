// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mediaplayer.h"

#include "mprisparsing.h"
#include "mediaplayerregistry.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDateTime>
#include <QDebug>
#include <QUrl>

#include <cmath>

namespace {
constexpr auto kObjectPath = "/org/mpris/MediaPlayer2";
constexpr auto kRootInterface = "org.mpris.MediaPlayer2";
constexpr auto kPlayerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto kPropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr double kMaxPlaybackRate = 16.0;

// artUrl 白名单与 Metadata 解析已拆分到 MprisParsing
}

MediaPlayer::MediaPlayer(QObject *parent)
    : QObject(parent)
{
    m_positionTimer.setInterval(500);
    m_positionTimer.setSingleShot(false);
    connect(&m_positionTimer, &QTimer::timeout, this, &MediaPlayer::updatePosition);

    if (MediaPlayers::instance()) {
        connect(MediaPlayers::instance(), &MediaPlayers::playersChanged,
                this, &MediaPlayer::onPlayersChanged);
        connect(MediaPlayers::instance(), &MediaPlayers::activeServiceChanged,
                this, &MediaPlayer::onPlayersChanged);
    }
    selectTarget();
}

QString MediaPlayer::mode() const
{
    return m_mode;
}

void MediaPlayer::setMode(const QString &mode)
{
    const QString normalized = mode == QLatin1String("locked")
        ? QStringLiteral("locked") : QStringLiteral("auto");
    if (m_mode == normalized)
        return;
    m_mode = normalized;
    Q_EMIT modeChanged();
    selectTarget();
}

QString MediaPlayer::service() const
{
    return m_service;
}

void MediaPlayer::setService(const QString &service)
{
    if (m_service == service)
        return;
    m_service = service;
    Q_EMIT serviceChanged();
    selectTarget();
}

QString MediaPlayer::activeService() const
{
    return m_activeService;
}

QString MediaPlayer::playerName() const
{
    if (MediaPlayers::instance())
        return MediaPlayers::instance()->playerName(m_activeService);
    return m_activeService;
}

bool MediaPlayer::connected() const
{
    return m_connected;
}

bool MediaPlayer::hasTrack() const
{
    return m_hasTrack;
}

QString MediaPlayer::playbackStatus() const
{
    return m_playbackStatus;
}

QString MediaPlayer::title() const
{
    return m_title;
}

QString MediaPlayer::artist() const
{
    return m_artist;
}

QString MediaPlayer::artUrl() const
{
    return m_artUrl;
}

qint64 MediaPlayer::positionMs() const
{
    return m_positionMs;
}

qint64 MediaPlayer::lengthMs() const
{
    return m_lengthMs;
}

bool MediaPlayer::canSeek() const
{
    return m_canSeek;
}

bool MediaPlayer::canControl() const
{
    return m_canControl;
}

bool MediaPlayer::canGoNext() const
{
    return m_canGoNext;
}

bool MediaPlayer::canGoPrevious() const
{
    return m_canGoPrevious;
}

bool MediaPlayer::canPlay() const
{
    return m_canPlay;
}

bool MediaPlayer::canPause() const
{
    return m_canPause;
}

void MediaPlayer::playPause()
{
    if (!m_connected || !m_canControl)
        return;
    if (m_playbackStatus == QLatin1String("Playing")) {
        if (!m_canPause)
            return;
    } else if (!m_canPlay) {
        return;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(
        m_activeService, QLatin1String(kObjectPath),
        QLatin1String(kPlayerInterface), QStringLiteral("PlayPause"));
    QDBusConnection::sessionBus().asyncCall(call);
}

void MediaPlayer::next()
{
    if (!m_connected || !m_canControl || !m_canGoNext)
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(
        m_activeService, QLatin1String(kObjectPath),
        QLatin1String(kPlayerInterface), QStringLiteral("Next"));
    QDBusConnection::sessionBus().asyncCall(call);
}

void MediaPlayer::previous()
{
    if (!m_connected || !m_canControl || !m_canGoPrevious)
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(
        m_activeService, QLatin1String(kObjectPath),
        QLatin1String(kPlayerInterface), QStringLiteral("Previous"));
    QDBusConnection::sessionBus().asyncCall(call);
}

void MediaPlayer::seek(qint64 ms)
{
    if (!m_connected || !m_canControl || !m_canSeek)
        return;
    if (ms < 0)
        ms = 0;
    if (m_lengthMs > 0 && ms > m_lengthMs)
        ms = m_lengthMs;

    QDBusMessage call;
    if (!m_trackId.isEmpty()) {
        call = QDBusMessage::createMethodCall(
            m_activeService, QLatin1String(kObjectPath),
            QLatin1String(kPlayerInterface), QStringLiteral("SetPosition"));
        call << QVariant::fromValue(QDBusObjectPath(m_trackId))
             << QVariant::fromValue<qlonglong>(ms * 1000);
    } else {
        call = QDBusMessage::createMethodCall(
            m_activeService, QLatin1String(kObjectPath),
            QLatin1String(kPlayerInterface), QStringLiteral("Seek"));
        call << QVariant::fromValue<qlonglong>((ms - m_positionMs) * 1000);
    }
    QDBusConnection::sessionBus().asyncCall(call);

    m_positionMs = ms;
    m_positionBaseMs = ms;
    m_positionBaseEpochMs = QDateTime::currentMSecsSinceEpoch();
    Q_EMIT stateChanged();
}

void MediaPlayer::refresh()
{
    fetchState();
}

void MediaPlayer::selectTarget()
{
    if (!MediaPlayers::instance())
        return;

    QString target;
    if (m_mode == QLatin1String("locked")) {
        if (MediaPlayers::instance()->isRunning(m_service))
            target = m_service;
    } else {
        target = MediaPlayers::instance()->activeService();
        if (target.isEmpty()) {
            const QStringList names = MediaPlayers::instance()->serviceNames();
            if (!names.isEmpty())
                target = names.first();
        }
    }

    if (target == m_activeService) {
        if (!target.isEmpty() && !m_connected && !m_fetchFailed)
            fetchState();
        return;
    }
    connectToService(target);
}

void MediaPlayer::connectToService(const QString &service)
{
    if (!m_activeService.isEmpty() && m_activeService != service) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.disconnect(m_activeService, QLatin1String(kObjectPath),
                       QLatin1String(kPropertiesInterface),
                       QStringLiteral("PropertiesChanged"),
                       this, SLOT(onPropertiesChanged(QDBusMessage)));
        bus.disconnect(m_activeService, QLatin1String(kObjectPath),
                       QLatin1String(kPlayerInterface),
                       QStringLiteral("Seeked"),
                       this, SLOT(onSeeked(QDBusMessage)));
    }

    if (m_watcher) {
        m_watcher->deleteLater();
        m_watcher = nullptr;
    }

    resetState();
    m_activeService = service;
    if (service.isEmpty()) {
        Q_EMIT stateChanged();
        return;
    }

    QDBusConnection bus = QDBusConnection::sessionBus();
    m_watcher = new QDBusServiceWatcher(service, bus,
                                        QDBusServiceWatcher::WatchForOwnerChange,
                                        this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered,
            this, &MediaPlayer::onServiceRegistered);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &MediaPlayer::onServiceUnregistered);

    bus.connect(service, QLatin1String(kObjectPath),
                QLatin1String(kPropertiesInterface),
                QStringLiteral("PropertiesChanged"),
                this, SLOT(onPropertiesChanged(QDBusMessage)));
    bus.connect(service, QLatin1String(kObjectPath),
                QLatin1String(kPlayerInterface),
                QStringLiteral("Seeked"),
                this, SLOT(onSeeked(QDBusMessage)));

    m_connected = true;
    m_fetchFailed = false;
    fetchState();
    Q_EMIT stateChanged();
}

void MediaPlayer::fetchState()
{
    if (m_activeService.isEmpty() || !m_connected)
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(
        m_activeService, QLatin1String(kObjectPath),
        QLatin1String(kPropertiesInterface), QStringLiteral("GetAll"));
    call << QLatin1String(kPlayerInterface);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, &MediaPlayer::onStateFetched);
}

void MediaPlayer::onStateFetched(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    QDBusPendingReply<QVariantMap> reply = *watcher;
    if (reply.isError()) {
        qWarning() << "MediaPlayer: GetAll failed:" << reply.error().message();
        if (m_activeService.isEmpty() || m_fetchFailed)
            return;
        resetState();
        m_fetchFailed = true;
        Q_EMIT stateChanged();
        return;
    }
    m_fetchFailed = false;
    const QVariantMap props = reply.value();
    applyProperties(props);
}

void MediaPlayer::onPropertiesChanged(const QDBusMessage &message)
{
    if (message.type() != QDBusMessage::SignalMessage
        || message.arguments().size() < 2) {
        return;
    }
    const QString interfaceName = message.arguments().at(0).toString();
    if (interfaceName != QLatin1String(kPlayerInterface)
        && interfaceName != QLatin1String(kRootInterface)) {
        return;
    }
    const QVariantMap changed = qdbus_cast<QVariantMap>(message.arguments().at(1));
    if (interfaceName == QLatin1String(kPlayerInterface))
        applyProperties(changed);
}

void MediaPlayer::onSeeked(const QDBusMessage &message)
{
    if (message.type() != QDBusMessage::SignalMessage
        || message.arguments().isEmpty()) {
        return;
    }
    const qlonglong positionUs = message.arguments().at(0).toLongLong();
    m_positionMs = positionUs / 1000;
    m_positionBaseMs = m_positionMs;
    m_positionBaseEpochMs = QDateTime::currentMSecsSinceEpoch();
    Q_EMIT stateChanged();
}

void MediaPlayer::onServiceRegistered(const QString &service)
{
    if (service == m_activeService) {
        m_connected = true;
        m_fetchFailed = false;
        fetchState();
        Q_EMIT stateChanged();
    }
}

void MediaPlayer::onServiceUnregistered(const QString &service)
{
    if (service != m_activeService)
        return;
    resetState();
    m_activeService.clear();
    Q_EMIT stateChanged();
    selectTarget();
}

void MediaPlayer::onPlayersChanged()
{
    selectTarget();
}

void MediaPlayer::applyProperties(const QVariantMap &props)
{
    bool changed = false;
    if (!props.isEmpty())
        m_fetchFailed = false;

    if (props.contains(QStringLiteral("PlaybackStatus"))) {
        const QString status = props.value(QStringLiteral("PlaybackStatus")).toString();
        if (m_playbackStatus != status) {
            m_playbackStatus = status;
            changed = true;
            if (status == QLatin1String("Playing")) {
                // 恢复播放时以当前位置为基准重新插值
                m_positionBaseMs = m_positionMs;
                m_positionBaseEpochMs = QDateTime::currentMSecsSinceEpoch();
            }
            startPositionTimerIfNeeded();
        }
    }

    if (props.contains(QStringLiteral("Position"))) {
        const qlonglong positionUs = props.value(QStringLiteral("Position")).toLongLong();
        m_positionMs = positionUs / 1000;
        m_positionBaseMs = m_positionMs;
        m_positionBaseEpochMs = QDateTime::currentMSecsSinceEpoch();
        changed = true;
    }

    if (props.contains(QStringLiteral("Metadata"))) {
        parseMetadata(props.value(QStringLiteral("Metadata")));
        changed = true;
    }

    if (props.contains(QStringLiteral("Rate"))) {
        const double rate = props.value(QStringLiteral("Rate")).toDouble();
        // 播放器上报的 Rate 是不可信输入：非有限或非正值回退 1.0，
        // 超出合理播放速度的值钳制到上限，避免浮点转整数时溢出。
        double normalizedRate = 1.0;
        if (std::isfinite(rate) && rate > 0.0)
            normalizedRate = qMin(rate, kMaxPlaybackRate);
        if (normalizedRate != m_rate) {
            m_rate = normalizedRate;
            // 变速后以当前位置为基准重新插值，避免按旧基准放大/缩小偏差
            m_positionBaseMs = m_positionMs;
            m_positionBaseEpochMs = QDateTime::currentMSecsSinceEpoch();
        }
    }

    const struct { const char *key; bool *target; } boolProps[] = {
        { "CanSeek", &m_canSeek },
        { "CanControl", &m_canControl },
        { "CanGoNext", &m_canGoNext },
        { "CanGoPrevious", &m_canGoPrevious },
        { "CanPlay", &m_canPlay },
        { "CanPause", &m_canPause }
    };
    for (const auto &prop : boolProps) {
        if (props.contains(QLatin1String(prop.key))) {
            const bool value = props.value(QLatin1String(prop.key)).toBool();
            if (*prop.target != value) {
                *prop.target = value;
                changed = true;
            }
        }
    }

    if (changed) {
        Q_EMIT stateChanged();
        startPositionTimerIfNeeded();
    }
}

void MediaPlayer::parseMetadata(const QVariant &metadata)
{
    const MprisParsing::TrackMetadata parsed = MprisParsing::parseMetadata(metadata);
    m_title = parsed.title;
    m_artist = parsed.artist;
    m_artUrl = parsed.artUrl;
    m_lengthMs = parsed.lengthMs;
    m_trackId = parsed.trackId;
    m_hasTrack = parsed.hasTrack;
}

void MediaPlayer::resetState()
{
    m_positionTimer.stop();
    m_fetchFailed = false;
    m_connected = false;
    m_hasTrack = false;
    m_playbackStatus.clear();
    m_title.clear();
    m_artist.clear();
    m_artUrl.clear();
    m_trackId.clear();
    m_positionMs = 0;
    m_lengthMs = 0;
    m_positionBaseMs = 0;
    m_positionBaseEpochMs = 0;
    m_rate = 1.0;
    m_canSeek = false;
    m_canControl = false;
    m_canGoNext = false;
    m_canGoPrevious = false;
    m_canPlay = false;
    m_canPause = false;
}

void MediaPlayer::updatePosition()
{
    if (m_playbackStatus != QLatin1String("Playing"))
        return;
    const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_positionBaseEpochMs;
    qint64 position = m_positionBaseMs + qint64(elapsed * m_rate);
    if (position < 0)
        position = 0;
    if (m_lengthMs > 0 && position > m_lengthMs)
        position = m_lengthMs;
    if (position != m_positionMs) {
        m_positionMs = position;
        Q_EMIT stateChanged();
    }
}

void MediaPlayer::startPositionTimerIfNeeded()
{
    if (m_playbackStatus == QLatin1String("Playing"))
        m_positionTimer.start();
    else
        m_positionTimer.stop();
}
