// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "timezones.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QDBusArgument>
#include <QDebug>
#include <QtConcurrent/QtConcurrentRun>
#include <QVariantMap>

namespace {

const char kService[] = "org.deepin.dde.Timedate1";
const char kPath[] = "/org/deepin/dde/Timedate1";
const char kInterface[] = "org.deepin.dde.Timedate1";
const char kPropertiesInterface[] = "org.freedesktop.DBus.Properties";

} // namespace


Timezones::Timezones(QObject *parent)
    : QObject(parent)
{
    m_timedate = new QDBusInterface(kService, kPath, kInterface,
                                    QDBusConnection::sessionBus(), this);
    m_db.setInterface(m_timedate);
    m_watcher = new QDBusServiceWatcher(kService, QDBusConnection::sessionBus(),
                                        QDBusServiceWatcher::WatchForRegistration
                                            | QDBusServiceWatcher::WatchForUnregistration,
                                        this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered,
            this, [this](const QString &) {
        refreshProperties();
        if (m_zoneOptionsRequested && m_zoneOptions.isEmpty()
            && !m_zoneOptionsLoading) {
            startZoneOptionsLoad();
        }
    });
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered,
            this, [this](const QString &) {
        // 服务重启后缓存可能过期，全部清空，待重新注册时再读取
        ++m_zoneOptionsGeneration;
        m_zoneOptionsLoading = false;
        m_db.clear();
        m_zoneOptions.clear();
        if (m_available) {
            m_available = false;
            Q_EMIT availableChanged();
        }
        if (!m_userTimezones.isEmpty()) {
            m_userTimezones.clear();
            Q_EMIT userTimezonesChanged();
        }
        if (!m_systemTimezone.isEmpty()) {
            m_systemTimezone.clear();
            Q_EMIT systemTimezoneChanged();
        }
    });

    QDBusConnection::sessionBus().connect(kService, kPath, kPropertiesInterface,
                                          QStringLiteral("PropertiesChanged"),
                                          this, SLOT(onPropertiesChanged(QDBusMessage)));
    refreshProperties();
}

bool Timezones::available() const
{
    return m_available;
}

QString Timezones::systemTimezone() const
{
    return m_systemTimezone;
}

QStringList Timezones::userTimezones() const
{
    return m_userTimezones;
}

QString Timezones::displayName(const QString &zoneId)
{
    if (zoneId.isEmpty())
        return QString();
    m_db.ensureFreshCaches();
    return m_db.details(zoneId).displayName;
}

int Timezones::offsetSeconds(const QString &zoneId)
{
    if (zoneId.isEmpty())
        return 0;
    m_db.ensureFreshCaches();
    return m_db.currentOffsetSeconds(m_db.details(zoneId));
}

QStringList Timezones::zoneIds()
{
    return m_db.zoneIds();
}

QString Timezones::firstZoneForOffset(int offsetHours, const QStringList &excludeZones)
{
    const QStringList zones = m_db.zonesForOffset(offsetHours);
    for (const QString &zone : zones) {
        if (!excludeZones.contains(zone))
            return zone;
    }
    return QString();
}

QVariantList Timezones::zoneOptions()
{
    if (m_zoneOptions.isEmpty())
        startZoneOptionsLoad();
    return m_zoneOptions;
}

void Timezones::startZoneOptionsLoad()
{
    m_zoneOptionsRequested = true;
    if (m_zoneOptionsLoading || !m_zoneOptions.isEmpty())
        return;
    if (!m_timedate || !m_timedate->isValid())
        return;

    m_zoneOptionsLoading = true;
    const int generation = ++m_zoneOptionsGeneration;
    if (!m_zoneOptionsWatcher) {
        m_zoneOptionsWatcher = new QFutureWatcher<QVariantList>(this);
    } else {
        disconnect(m_zoneOptionsWatcher, nullptr, this, nullptr);
    }

    connect(m_zoneOptionsWatcher, &QFutureWatcher<QVariantList>::finished,
            this, [this, generation]() {
        if (generation != m_zoneOptionsGeneration)
            return;

        m_zoneOptions = m_zoneOptionsWatcher->result();
        m_zoneOptionsLoading = false;
        Q_EMIT zoneOptionsChanged();
    });

    m_zoneOptionsWatcher->setFuture(QtConcurrent::run(&TimezoneDb::fetchZoneOptions));
}

void Timezones::refreshProperties()
{
    const bool nextAvailable = m_timedate && m_timedate->isValid();
    QStringList nextUsers;
    QString nextSystem;
    if (nextAvailable) {
        nextUsers = m_timedate->property("UserTimezones").toStringList();
        nextSystem = m_timedate->property("Timezone").toString();
    }

    if (nextAvailable != m_available) {
        m_available = nextAvailable;
        Q_EMIT availableChanged();
    }
    if (m_userTimezones != nextUsers) {
        m_userTimezones = nextUsers;
        Q_EMIT userTimezonesChanged();
    }
    if (m_systemTimezone != nextSystem) {
        m_systemTimezone = nextSystem;
        Q_EMIT systemTimezoneChanged();
    }
}

void Timezones::onPropertiesChanged(const QDBusMessage &message)
{
    const QList<QVariant> args = message.arguments();
    if (args.size() < 2 || args.at(0).toString() != QLatin1String(kInterface))
        return;

    bool usersChanged = false;
    bool systemChanged = false;

    const QVariantMap changed = qdbus_cast<QVariantMap>(args.at(1));
    if (changed.contains(QStringLiteral("UserTimezones"))) {
        const QStringList next = changed.value(QStringLiteral("UserTimezones")).toStringList();
        if (m_userTimezones != next) {
            m_userTimezones = next;
            usersChanged = true;
        }
    }
    if (changed.contains(QStringLiteral("Timezone"))) {
        const QString next = changed.value(QStringLiteral("Timezone")).toString();
        if (m_systemTimezone != next) {
            m_systemTimezone = next;
            systemChanged = true;
        }
    }

    // 部分 D-Bus 服务以 invalidated 而非 changed 报告属性变化
    if (args.size() > 2) {
        const QStringList invalidated = qdbus_cast<QStringList>(args.at(2));
        for (const QString &name : invalidated) {
            if (name == QLatin1String("UserTimezones")) {
                const QStringList next =
                    m_timedate->property("UserTimezones").toStringList();
                if (m_userTimezones != next) {
                    m_userTimezones = next;
                    usersChanged = true;
                }
            } else if (name == QLatin1String("Timezone")) {
                const QString next = m_timedate->property("Timezone").toString();
                if (m_systemTimezone != next) {
                    m_systemTimezone = next;
                    systemChanged = true;
                }
            }
        }
    }

    if (usersChanged)
        Q_EMIT userTimezonesChanged();
    if (systemChanged)
        Q_EMIT systemTimezoneChanged();
}


