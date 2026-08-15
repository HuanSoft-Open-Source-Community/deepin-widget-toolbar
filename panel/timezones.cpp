// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "timezones.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QDate>
#include <QDateTime>
#include <QDebug>
#include <QTime>
#include <QTimeZone>
#include <QtConcurrent/QtConcurrentRun>
#include <QVariant>
#include <QVariantMap>

namespace {

const char kService[] = "org.deepin.dde.Timedate1";
const char kPath[] = "/org/deepin/dde/Timedate1";
const char kInterface[] = "org.deepin.dde.Timedate1";
const char kPropertiesInterface[] = "org.freedesktop.DBus.Properties";

// GetZoneInfo 的返回签名为 (ssi(xxi))：
//   s 时区 id、s 本地化地区名、i 标准 UTC 偏移秒、
//   (x x i) = (DST 进入时间戳, DST 离开时间戳, DST 期间的偏移秒)。
// 控制中心 datetime 插件按同样方式解包。
bool decodeZoneInfo(const QVariant &value, QString *name, int *standardOffset,
                    qint64 *dstEnter, qint64 *dstLeave, int *dstOffset)
{
    if (!value.canConvert<QDBusArgument>())
        return false;

    // Qt 6 的读取重载是 const 版本，非 const 会误用写入分支导致解包失败
    const QDBusArgument argument = value.value<QDBusArgument>();
    QString zoneName;
    QString cityName;
    qint32 standard = 0;
    qint64 enter = 0;
    qint64 leave = 0;
    qint32 dst = 0;

    argument.beginStructure();
    argument >> zoneName >> cityName >> standard;
    argument.beginStructure();
    argument >> enter >> leave >> dst;
    argument.endStructure();
    argument.endStructure();

    if (name) {
        if (!cityName.isEmpty()) {
            *name = cityName;
        } else {
            const int slash = zoneName.lastIndexOf(QLatin1Char('/'));
            *name = slash >= 0 ? zoneName.mid(slash + 1) : zoneName;
        }
    }
    if (standardOffset)
        *standardOffset = standard;
    if (dstEnter)
        *dstEnter = enter;
    if (dstLeave)
        *dstLeave = leave;
    if (dstOffset)
        *dstOffset = dst;
    return true;
}

QString prettifyZoneName(QString name)
{
    return name.replace(QLatin1Char('_'), QLatin1Char(' '));
}

QVariantList fetchZoneOptions()
{
    QVariantList options;
    QDBusInterface timedate(kService, kPath, kInterface,
                            QDBusConnection::sessionBus());
    if (!timedate.isValid())
        return options;

    const QDBusMessage listReply = timedate.call(QStringLiteral("GetZoneList"));
    if (listReply.type() == QDBusMessage::ErrorMessage || listReply.arguments().isEmpty())
        return options;

    const QStringList ids = listReply.arguments().constFirst().toStringList();
    options.reserve(ids.size());
    for (const QString &id : ids) {
        QString name;
        const QDBusMessage reply = timedate.call(QStringLiteral("GetZoneInfo"), id);
        if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty()) {
            decodeZoneInfo(reply.arguments().constFirst(), &name,
                           nullptr, nullptr, nullptr, nullptr);
        }

        if (name.isEmpty()) {
            const int slash = id.lastIndexOf(QLatin1Char('/'));
            name = slash >= 0 ? id.mid(slash + 1) : id;
        }

        QVariantMap entry;
        entry.insert(QStringLiteral("value"), id);
        entry.insert(QStringLiteral("label"), prettifyZoneName(name));
        options.append(entry);
    }
    return options;
}

} // namespace

Timezones::Timezones(QObject *parent)
    : QObject(parent)
{
    m_timedate = new QDBusInterface(kService, kPath, kInterface,
                                    QDBusConnection::sessionBus(), this);
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
        m_detailsCache.clear();
        m_zoneIds.clear();
        m_zoneIdsLoaded = false;
        m_offsetZonesCache.clear();
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
    ensureFreshCaches();
    return details(zoneId).displayName;
}

int Timezones::offsetSeconds(const QString &zoneId)
{
    if (zoneId.isEmpty())
        return 0;
    ensureFreshCaches();
    return currentOffsetSeconds(details(zoneId));
}

QStringList Timezones::zoneIds()
{
    if (m_zoneIdsLoaded)
        return m_zoneIds;

    m_zoneIdsLoaded = true;
    if (!m_timedate || !m_timedate->isValid())
        return m_zoneIds;

    const QDBusMessage reply = m_timedate->call(QStringLiteral("GetZoneList"));
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        qWarning() << "Timezones: GetZoneList failed"
                   << reply.errorName() << reply.errorMessage();
        return m_zoneIds;
    }

    m_zoneIds = reply.arguments().constFirst().toStringList();
    return m_zoneIds;
}

QString Timezones::firstZoneForOffset(int offsetHours, const QStringList &excludeZones)
{
    const QStringList zones = zonesForOffset(offsetHours);
    for (const QString &zone : zones) {
        if (!excludeZones.contains(zone))
            return zone;
    }
    return QString();
}

QStringList Timezones::zonesForOffset(int offsetHours)
{
    ensureFreshCaches();
    const int targetSeconds = offsetHours * 3600;
    const auto it = m_offsetZonesCache.constFind(targetSeconds);
    if (it != m_offsetZonesCache.constEnd())
        return it.value();

    QStringList found;
    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    const QStringList ids = zoneIds();
    for (const QString &id : ids) {
        const QTimeZone zone(id.toUtf8());
        if (!zone.isValid())
            continue;
        if (zone.offsetFromUtc(nowUtc) == targetSeconds)
            found.append(id);
    }
    m_offsetZonesCache.insert(targetSeconds, found);
    return found;
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

    m_zoneOptionsWatcher->setFuture(QtConcurrent::run(&fetchZoneOptions));
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

Timezones::ZoneDetails Timezones::fetchZoneDetails(const QString &zoneId)
{
    ZoneDetails result;
    if (!m_timedate || !m_timedate->isValid())
        return result;

    const QDBusMessage reply = m_timedate->call(QStringLiteral("GetZoneInfo"), zoneId);
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
        qWarning() << "Timezones: GetZoneInfo failed for" << zoneId
                   << reply.errorName() << reply.errorMessage();
        return result;
    }

    QString name;
    int standardOffset = 0;
    qint64 dstEnter = 0;
    qint64 dstLeave = 0;
    int dstOffset = 0;
    if (!decodeZoneInfo(reply.arguments().constFirst(), &name, &standardOffset,
                        &dstEnter, &dstLeave, &dstOffset))
        return result;

    result.valid = true;
    result.displayName = prettifyName(name);
    result.standardOffsetSeconds = standardOffset;
    result.dstEnter = dstEnter;
    result.dstLeave = dstLeave;
    result.dstOffsetSeconds = dstOffset;
    return result;
}

Timezones::ZoneDetails Timezones::details(const QString &zoneId)
{
    const auto it = m_detailsCache.constFind(zoneId);
    if (it != m_detailsCache.constEnd())
        return it.value();

    ZoneDetails result = fetchZoneDetails(zoneId);
    if (!result.valid) {
        // GetZoneInfo 失败时仍给出可读回退名（时区 id 末段），偏移记为 0
        const int slash = zoneId.lastIndexOf(QLatin1Char('/'));
        result.displayName =
            prettifyName(slash >= 0 ? zoneId.mid(slash + 1) : zoneId);
    }
    m_detailsCache.insert(zoneId, result);
    return result;
}

void Timezones::ensureFreshCaches()
{
    // GetZoneInfo 的 DST 区间按“调用当年的日历”计算，跨年后窗口失效，
    // 按天清理时区详情缓存即可保证新一年重新拉取。
    const QDate today = QDate::currentDate();
    if (m_detailsDate != today) {
        m_detailsDate = today;
        m_detailsCache.clear();
    }

    // “偏移 → 第一个时区”依赖当前是否处于 DST（同名偏移的季节性归属会变化），
    // 按小时清理，配合 QML 每小时重建，DST 切换后最迟一小时内校正表盘名。
    const int hour = QTime::currentTime().hour();
    if (m_offsetCacheHour != hour) {
        m_offsetCacheHour = hour;
        m_offsetZonesCache.clear();
    }
}

int Timezones::currentOffsetSeconds(const ZoneDetails &details) const
{
    if (!details.valid)
        return 0;
    if (details.dstEnter > 0 && details.dstLeave >= details.dstEnter
        && details.dstOffsetSeconds != 0) {
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        if (now >= details.dstEnter && now <= details.dstLeave)
            return details.dstOffsetSeconds;
    }
    return details.standardOffsetSeconds;
}

QString Timezones::prettifyName(QString name)
{
    return prettifyZoneName(name);
}
