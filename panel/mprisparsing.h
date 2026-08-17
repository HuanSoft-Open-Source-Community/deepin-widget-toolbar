// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QVariant>

// MPRIS 元数据的纯解析工具（从 MediaPlayer 拆分）：
// metadata 字典 → 曲目字段；artUrl 来源白名单校验。
namespace MprisParsing {

struct TrackMetadata
{
    QString title;
    QString artist;
    QString artUrl;
    qint64 lengthMs = 0;
    QString trackId;
    bool hasTrack = false;
};

// 解析 MPRIS Metadata 字典（QVariantMap 或 QDBusArgument 形式）
TrackMetadata parseMetadata(const QVariant &metadata);

// artUrl 白名单：仅允许 file/http/https，其余（含空）一律拒绝
bool isAllowedArtUrl(const QString &url);

} // namespace MprisParsing
