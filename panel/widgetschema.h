// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// manifest 配置 schema 的纯函数工具：
// 本地化字段展开、QML 消费转换、默认配置与合法 key 提取。
namespace WidgetSchema {

// manifest 多语言字段键：name[zh_CN] 形式
QString localeKey(const QString &base);

// 将 manifest 配置项 schema 转为 QML 可消费的 QVariantList，
// 并把 label[zh_CN] 等本地化字段展开为 label。
QVariantList parseSettingsSchema(const QJsonArray &entries);

QStringList schemaKeys(const QVariantList &schema);
QVariantMap defaultConfig(const QVariantList &schema);

// manifest settings 已知类型集合（含宿主内置扩展，1.10 新增 slider；
// 1.11 起设置项可选声明 lockWhen 联动字段，类型集合本身不变）
bool isKnownSettingType(const QString &type);

// image 类型值合法性：空串 = 未设置；非空必须是相对 dataDir 的相对路径
//（不以 "/" 开头、不含 ".."），防止配置把图片指到实例目录之外
bool isValidImageValue(const QString &value);

} // namespace WidgetSchema
