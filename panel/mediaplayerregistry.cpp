// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mediaplayerregistry.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>

#include <algorithm>

namespace {
constexpr auto kMprisPrefix = "org.mpris.MediaPlayer2.";
constexpr auto kObjectPath = "/org/mpris/MediaPlayer2";
constexpr auto kRootInterface = "org.mpris.MediaPlayer2";
constexpr auto kPlayerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto kPropertiesInterface = "org.freedesktop.DBus.Properties";

bool isMprisService(const QString &service)
{
    return service.startsWith(QLatin1String(kMprisPrefix));
}
}

// D-Bus 信号到达时，QDBusMessage::service() 返回的是发送者的唯一连接名
// （如 :1.23），而不是 well-known 服务名（如 org.mpris.MediaPlayer2.vlc）。
// 每个 MPRIS 服务使用一个持有 well-known 名的中继对象接收信号，从而把
// “活跃播放器”正确归属到注册表里的服务名。
class MprisSignalRelay : public QObject
{
    Q_OBJECT
public:
    MprisSignalRelay(const QString &service, MediaPlayers *owner)
        : QObject(owner)
        , m_service(service)
        , m_owner(owner)
    {
    }

public Q_SLOTS:
    void onPlayerSignal(const QDBusMessage &message)
    {
        Q_UNUSED(message)
        if (m_owner)
            m_owner->notePlayerSignal(m_service);
    }

private:
    QString m_service;
    MediaPlayers *m_owner = nullptr;
};

MediaPlayers *MediaPlayers::s_instance = nullptr;

MediaPlayers *MediaPlayers::instance()
{
    return s_instance;
}

MediaPlayers::MediaPlayers(QObject *parent)
    : QObject(parent)
{
    s_instance = this;

    QDBusConnection bus = QDBusConnection::sessionBus();
    // 监听播放器上线/下线：NameOwnerChanged 对前缀服务同样适用
    bus.connect(QStringLiteral("org.freedesktop.DBus"),
                QStringLiteral("/org/freedesktop/DBus"),
                QStringLiteral("org.freedesktop.DBus"),
                QStringLiteral("NameOwnerChanged"),
                this,
                SLOT(onNameOwnerChanged(QString, QString, QString)));

    // 面板启动时枚举一次已有的 MPRIS 服务
    QDBusMessage listCall = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("ListNames"));
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        bus.asyncCall(listCall), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, &MediaPlayers::onRegisteredServiceNames);
}

MediaPlayers::~MediaPlayers()
{
    if (s_instance == this)
        s_instance = nullptr;

    const auto relays = m_relays.values();
    for (auto *relay : relays)
        delete relay;
    m_relays.clear();
}

QVariantList MediaPlayers::players() const
{
    QVariantList result;
    for (const QString &service : m_services) {
        QVariantMap item;
        item.insert(QStringLiteral("service"), service);
        item.insert(QStringLiteral("name"), playerName(service));
        result.append(item);
    }
    return result;
}

QString MediaPlayers::activeService() const
{
    return m_activeService;
}

QString MediaPlayers::playerName(const QString &service) const
{
    const QString name = m_names.value(service);
    if (!name.isEmpty())
        return name;
    // 未取到 Identity 时用服务名后缀兜底
    if (service.startsWith(QLatin1String(kMprisPrefix)))
        return service.mid(QLatin1String(kMprisPrefix).size());
    return service;
}

QStringList MediaPlayers::serviceNames() const
{
    return m_services;
}

bool MediaPlayers::isRunning(const QString &service) const
{
    return m_services.contains(service);
}

void MediaPlayers::onNameOwnerChanged(const QString &name,
                                      const QString &oldOwner,
                                      const QString &newOwner)
{
    Q_UNUSED(oldOwner)
    if (!isMprisService(name))
        return;
    if (newOwner.isEmpty())
        removeService(name);
    else
        addService(name);
}

void MediaPlayers::onRegisteredServiceNames(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    QDBusPendingReply<QStringList> reply = *watcher;
    if (reply.isError())
        return;
    const QStringList names = reply.value();
    for (const QString &service : names) {
        if (isMprisService(service))
            addService(service);
    }
}

void MediaPlayers::addService(const QString &service)
{
    if (m_services.contains(service))
        return;
    m_services.append(service);
    std::sort(m_services.begin(), m_services.end());
    connectToService(service);
    emit playersChanged();

    // 新服务上线即视为候选活跃播放器（后续 PropertiesChanged 会刷新）
    if (m_activeService.isEmpty())
        setActiveService(service);

    // 异步读取 Identity：失败时保留服务名后缀兜底
    QDBusMessage call = QDBusMessage::createMethodCall(
        service,
        QLatin1String(kObjectPath),
        QLatin1String(kPropertiesInterface),
        QStringLiteral("Get"));
    call << QLatin1String(kRootInterface) << QStringLiteral("Identity");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, service](QDBusPendingCallWatcher *w) {
                onIdentityFetched(service, w);
            });
}

void MediaPlayers::removeService(const QString &service)
{
    if (!m_services.removeOne(service))
        return;
    disconnectFromService(service);
    m_names.remove(service);
    if (m_activeService == service) {
        m_activeService = m_services.isEmpty() ? QString() : m_services.first();
        Q_EMIT activeServiceChanged();
    }
    Q_EMIT playersChanged();
}

void MediaPlayers::connectToService(const QString &service)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    auto *relay = new MprisSignalRelay(service, this);
    m_relays.insert(service, relay);

    bus.connect(service,
                QLatin1String(kObjectPath),
                QLatin1String(kPropertiesInterface),
                QStringLiteral("PropertiesChanged"),
                relay,
                SLOT(onPlayerSignal(QDBusMessage)));
    bus.connect(service,
                QLatin1String(kObjectPath),
                QLatin1String(kPlayerInterface),
                QStringLiteral("Seeked"),
                relay,
                SLOT(onPlayerSignal(QDBusMessage)));
}

void MediaPlayers::disconnectFromService(const QString &service)
{
    auto *relay = m_relays.take(service);
    if (!relay)
        return;

    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.disconnect(service,
                   QLatin1String(kObjectPath),
                   QLatin1String(kPropertiesInterface),
                   QStringLiteral("PropertiesChanged"),
                   relay,
                   SLOT(onPlayerSignal(QDBusMessage)));
    bus.disconnect(service,
                   QLatin1String(kObjectPath),
                   QLatin1String(kPlayerInterface),
                   QStringLiteral("Seeked"),
                   relay,
                   SLOT(onPlayerSignal(QDBusMessage)));

    delete relay;
}

void MediaPlayers::notePlayerSignal(const QString &service)
{
    if (!isMprisService(service) || !m_services.contains(service))
        return;
    setActiveService(service);
}

void MediaPlayers::onIdentityFetched(const QString &service, QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    QDBusPendingReply<QVariant> reply = *watcher;
    if (reply.isError())
        return;
    const QString name = reply.value().toString();
    if (name.isEmpty())
        return;
    if (m_names.value(service) == name)
        return;
    m_names.insert(service, name);
    Q_EMIT playersChanged();
}

void MediaPlayers::setActiveService(const QString &service)
{
    if (m_activeService == service)
        return;
    m_activeService = service;
    Q_EMIT activeServiceChanged();
}

#include "mediaplayerregistry.moc"
