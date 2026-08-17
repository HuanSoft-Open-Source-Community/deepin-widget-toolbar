// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDate>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantList>

class QDBusInterface;

// 时区数据的读取与缓存层（从 Timezones 代理拆分）：
// 封装对 org.deepin.dde.Timedate1 的 GetZoneInfo/GetZoneList 调用、
// DST 区间解析、详情与"偏移→时区"缓存。D-Bus 连接对象由调用方注入，
// 不持有代理生命周期；服务重启后调用 clear() 清空缓存。
class TimezoneDb
{
public:
    struct ZoneDetails
    {
        QString displayName;
        int standardOffsetSeconds = 0;
        qint64 dstEnter = 0;
        qint64 dstLeave = 0;
        int dstOffsetSeconds = 0;
        bool valid = false;
    };

    TimezoneDb() = default;
    explicit TimezoneDb(QDBusInterface *timedate);
    // D-Bus 连接对象由代理创建后注入（代理构造顺序需要）
    void setInterface(QDBusInterface *timedate);

    // 时区详情（带缓存）：GetZoneInfo 失败时给出可读回退名（id 末段），偏移记 0
    ZoneDetails details(const QString &zoneId);
    // 当前 UTC 偏移（秒）：处于 DST 区间内用 DST 偏移，否则标准偏移
    int currentOffsetSeconds(const ZoneDetails &details) const;
    // 当前 UTC 偏移等于 offsetHours 的全部时区 id（带缓存）
    QStringList zonesForOffset(int offsetHours);
    // 控制中心时区选择器使用的全部时区 id（GetZoneList 顺序，带缓存）
    QStringList zoneIds();
    // 时区下拉选项 [{value, label}]，按 GetZoneList 顺序（独立 D-Bus 连接，
    // 可在后台线程调用）
    static QVariantList fetchZoneOptions();
    // 按日历/小时清理缓存（跨年 DST 区间失效、季节偏移归属变化）
    void ensureFreshCaches();
    // 服务重启后清空全部缓存
    void clear();

private:
    ZoneDetails fetchZoneDetails(const QString &zoneId);
    static bool decodeZoneInfo(const QVariant &value, QString *name, int *standardOffset,
                               qint64 *dstEnter, qint64 *dstLeave, int *dstOffset);
    static QString prettifyName(QString name);

    QDBusInterface *m_timedate = nullptr;
    QHash<QString, ZoneDetails> m_detailsCache;
    QHash<int, QStringList> m_offsetZonesCache;
    QStringList m_zoneIds;
    bool m_zoneIdsLoaded = false;
    QDate m_detailsDate;
    int m_offsetCacheHour = -1;
};
