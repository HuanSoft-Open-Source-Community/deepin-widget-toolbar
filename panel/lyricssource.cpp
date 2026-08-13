// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "lyricssource.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

namespace {
constexpr auto kService = "org.mpris.MediaPlayer2.ter_music";
constexpr auto kObjectPath = "/org/mpris/MediaPlayer2";
constexpr auto kInterface = "org.yxzl.ter_music.Lyrics";
constexpr auto kGetLyrics = "GetLyrics";
constexpr auto kLyricsChanged = "LyricsChanged";
}

LyricsSource::LyricsSource(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    // 监听播放器总线上线/下线（WatchForOwnerChange 只通知变化，不含当前状态）
    auto *watcher = new QDBusServiceWatcher(QString::fromLatin1(kService),
                                            bus,
                                            QDBusServiceWatcher::WatchForOwnerChange,
                                            this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, &LyricsSource::onServiceRegistered);
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, &LyricsSource::onServiceUnregistered);

    // 订阅歌词快照变化：服务未运行期间不会收到消息，上线后信号自然送达
    bus.connect(QString::fromLatin1(kService),
                QString::fromLatin1(kObjectPath),
                QString::fromLatin1(kInterface),
                QString::fromLatin1(kLyricsChanged),
                this,
                SLOT(onLyricsChanged(QString)));

    // 面板启动时播放器可能已在运行：同步一次连接状态并拉取快照
    if (bus.interface() && bus.interface()->isServiceRegistered(QString::fromLatin1(kService)))
        onServiceRegistered(QString::fromLatin1(kService));
}

bool LyricsSource::connected() const
{
    return m_connected;
}

bool LyricsSource::hasTrack() const
{
    return m_hasTrack;
}

bool LyricsSource::hasLyrics() const
{
    return m_hasLyrics;
}

bool LyricsSource::hasTimestamps() const
{
    return m_hasTimestamps;
}

QString LyricsSource::activeText() const
{
    return m_activeText;
}

QString LyricsSource::nextText() const
{
    return m_nextText;
}

QString LyricsSource::trackId() const
{
    return m_trackId;
}

void LyricsSource::refresh()
{
    const QDBusMessage call = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterface),
        QString::fromLatin1(kGetLyrics));

    auto *callWatcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(call), this);
    connect(callWatcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        QDBusPendingReply<QString> reply = *watcher;
        if (reply.isError()) {
            qWarning() << "LyricsSource: GetLyrics failed:" << reply.error().message();
            return;
        }
        applySnapshot(reply.value());
    });
}

void LyricsSource::onServiceRegistered(const QString &service)
{
    Q_UNUSED(service)
    if (m_connected)
        return;
    m_connected = true;
    Q_EMIT connectedChanged();
    refresh();
}

void LyricsSource::onServiceUnregistered(const QString &service)
{
    Q_UNUSED(service)
    if (!m_connected)
        return;
    m_connected = false;
    Q_EMIT connectedChanged();
    resetSnapshot();
    Q_EMIT lyricsChanged();
}

void LyricsSource::onLyricsChanged(const QString &payload)
{
    applySnapshot(payload);
}

void LyricsSource::applySnapshot(const QString &payload)
{
    if (payload.isEmpty() || payload == m_lastPayload)
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(payload.toUtf8());
    if (!doc.isObject())
        return;
    const QJsonObject obj = doc.object();

    // A/B 双缓冲：active_line 指向当前槽位，另一槽位为下一句
    const QString activeLine = obj.value("active_line").toString();
    const QJsonObject lineA = obj.value("line_a").toObject();
    const QJsonObject lineB = obj.value("line_b").toObject();
    const QString textA = lineA.value("text").toString();
    const QString textB = lineB.value("text").toString();

    m_hasLyrics = obj.value("has_lyrics").toBool();
    m_hasTimestamps = obj.value("has_timestamps").toBool();
    m_trackId = obj.value("track_id").toString();
    m_hasTrack = !m_trackId.isEmpty();

    if (activeLine == QLatin1String("B")) {
        m_activeText = textB;
        m_nextText = textA;
    } else {
        // active_line 为 "A" 或 null 时均以 line_a 为当前句：
        // 无时间戳歌词固定 A 为当前句，null 仅表示当前无活动行
        m_activeText = textA;
        m_nextText = textB;
    }

    m_lastPayload = payload;
    Q_EMIT lyricsChanged();
}

void LyricsSource::resetSnapshot()
{
    m_hasTrack = false;
    m_hasLyrics = false;
    m_hasTimestamps = false;
    m_activeText.clear();
    m_nextText.clear();
    m_trackId.clear();
    m_lastPayload.clear();
}
