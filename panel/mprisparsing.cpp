// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "mprisparsing.h"

#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QUrl>

namespace MprisParsing {

bool isAllowedArtUrl(const QString &url)
{
    if (url.isEmpty())
        return false;
    const QUrl parsed(url);
    const QString scheme = parsed.scheme().toLower();
    return scheme == QLatin1String("file")
        || scheme == QLatin1String("http")
        || scheme == QLatin1String("https");
}

TrackMetadata parseMetadata(const QVariant &metadata)
{
    TrackMetadata result;
    QVariantMap map;
    if (metadata.canConvert<QVariantMap>()) {
        map = metadata.toMap();
    } else if (metadata.canConvert<QDBusArgument>()) {
        map = qdbus_cast<QVariantMap>(metadata.value<QDBusArgument>());
    } else {
        return result;
    }

    result.title = map.value(QStringLiteral("xesam:title")).toString();
    const QVariant artistValue = map.value(QStringLiteral("xesam:artist"));
    if (artistValue.canConvert<QStringList>()) {
        result.artist = artistValue.toStringList().join(QStringLiteral(", "));
    } else if (artistValue.canConvert<QString>()) {
        result.artist = artistValue.toString();
    } else {
        result.artist.clear();
    }
    result.artUrl = map.value(QStringLiteral("mpris:artUrl")).toString();
    if (!isAllowedArtUrl(result.artUrl))
        result.artUrl.clear();
    result.lengthMs = map.value(QStringLiteral("mpris:length")).toLongLong() / 1000;
    result.trackId = map.value(QStringLiteral("mpris:trackid")).value<QDBusObjectPath>().path();
    result.hasTrack = !result.title.isEmpty() || !result.artist.isEmpty()
        || !result.trackId.isEmpty();
    return result;
}

} // namespace MprisParsing
