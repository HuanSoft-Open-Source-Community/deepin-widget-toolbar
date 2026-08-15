// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QFutureWatcher>
#include <QDate>
#include <QHash>
#include <QObject>
#include <QStringList>

class QDBusInterface;
class QDBusMessage;
class QDBusServiceWatcher;

// 时区数据代理（QML 单例 org.deepin.widgettoolbar/Timezones）：
// 世界时间小组件通过它读取 DDE 控制中心“时间设置”维护的时区列表与本地化名称。
// 数据源为会话总线 org.deepin.dde.Timedate1（dde-session-daemon），与控制中心
// datetime 插件使用的是同一接口：
//   - UserTimezones：控制中心维护的用户时区 id 列表（首个为系统时区）；
//   - GetZoneInfo(zone)：返回 (时区 id, 本地化地区名, 标准 UTC 偏移秒, DST 区间)；
//   - GetZoneList()：控制中心时区选择器使用的完整时区列表。
//
// 小组件自身不允许直接访问系统 D-Bus，时区能力统一由本代理中转，与 Lyrics 同理。
class Timezones : public QObject
{
    Q_OBJECT
    // 会话总线上的 Timedate1 服务当前是否可用
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // 系统时区 id（如 Asia/Shanghai）
    Q_PROPERTY(QString systemTimezone READ systemTimezone NOTIFY systemTimezoneChanged)
    // 控制中心“时间设置”维护的用户时区 id 列表（首个为系统时区）
    Q_PROPERTY(QStringList userTimezones READ userTimezones NOTIFY userTimezonesChanged)

public:
    explicit Timezones(QObject *parent = nullptr);

    bool available() const;
    QString systemTimezone() const;
    QStringList userTimezones() const;

    // zoneId 的本地化地区名；缺失时回退为 zoneId 末段并把下划线转成空格
    Q_INVOKABLE QString displayName(const QString &zoneId);
    // zoneId 的当前 UTC 偏移（秒）。以 GetZoneInfo 返回的标准偏移为基准，
    // 处于 DST 区间内时切换为 DST 偏移，保证与控制中心口径一致。
    Q_INVOKABLE int offsetSeconds(const QString &zoneId);
    // 控制中心时区选择器使用的全部时区 id（GetZoneList 顺序）
    Q_INVOKABLE QStringList zoneIds();
    // 当前 UTC 偏移等于 offsetHours 的时区中，按 GetZoneList 顺序、跳过
    // excludeZones 后取第一个 id；无可用时返回空串。用于补位表盘
    // “同一偏移有多个时区名时缺省第一个”，并配合跨实例地区唯一性。
    Q_INVOKABLE QString firstZoneForOffset(int offsetHours, const QStringList &excludeZones);
    // 时区下拉选项（[{value: 时区id, label: 本地化地区名}]），按 GetZoneList 顺序。
    // 首次调用返回当前缓存并触发后台加载，完成后发出 zoneOptionsChanged()。
    Q_INVOKABLE QVariantList zoneOptions();

Q_SIGNALS:
    void availableChanged();
    void systemTimezoneChanged();
    void userTimezonesChanged();
    void zoneOptionsChanged();

private Q_SLOTS:
    void refreshProperties();
    void onPropertiesChanged(const QDBusMessage &message);

private:
    struct ZoneDetails
    {
        QString displayName;
        int standardOffsetSeconds = 0;
        qint64 dstEnter = 0;
        qint64 dstLeave = 0;
        int dstOffsetSeconds = 0;
        bool valid = false;
    };

    ZoneDetails fetchZoneDetails(const QString &zoneId);
    ZoneDetails details(const QString &zoneId);
    int currentOffsetSeconds(const ZoneDetails &details) const;
    QStringList zonesForOffset(int offsetHours);
    void ensureFreshCaches();
    void startZoneOptionsLoad();
    static QString prettifyName(QString name);

    QDBusInterface *m_timedate = nullptr;
    QDBusServiceWatcher *m_watcher = nullptr;
    bool m_available = false;
    QString m_systemTimezone;
    QStringList m_userTimezones;
    QStringList m_zoneIds;
    bool m_zoneIdsLoaded = false;
    QHash<QString, ZoneDetails> m_detailsCache;
    QHash<int, QStringList> m_offsetZonesCache;
    QVariantList m_zoneOptions;
    QDate m_detailsDate;
    int m_offsetCacheHour = -1;
    QFutureWatcher<QVariantList> *m_zoneOptionsWatcher = nullptr;
    bool m_zoneOptionsLoading = false;
    bool m_zoneOptionsRequested = false;
    int m_zoneOptionsGeneration = 0;
};
