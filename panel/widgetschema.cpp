// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetschema.h"

#include <QLocale>

namespace WidgetSchema {

QString localeKey(const QString &base)
{
    const QString locale = QLocale::system().name();   // 如 zh_CN / en_US
    if (!locale.isEmpty())
        return base + "[" + locale + "]";
    return base;
}

QVariantList parseSettingsSchema(const QJsonArray &entries)
{
    QVariantList result;
    const QString localizedLabel = localeKey("label");

    for (const QJsonValue &value : entries) {
        if (!value.isObject())
            continue;
        const QJsonObject obj = value.toObject();
        QVariantMap item = obj.toVariantMap();
        if (obj.contains(localizedLabel))
            item.insert(QStringLiteral("label"), obj.value(localizedLabel).toString());

        const QJsonArray options = obj.value("options").toArray();
        if (!options.isEmpty()) {
            QVariantList localizedOptions;
            for (const QJsonValue &option : options) {
                if (!option.isObject())
                    continue;
                const QJsonObject optionObj = option.toObject();
                QVariantMap optionMap = optionObj.toVariantMap();
                if (optionObj.contains(localizedLabel))
                    optionMap.insert(QStringLiteral("label"), optionObj.value(localizedLabel).toString());
                localizedOptions.append(optionMap);
            }
            item.insert(QStringLiteral("options"), localizedOptions);
        }

        if (!item.value(QStringLiteral("key")).toString().isEmpty()
            && !item.value(QStringLiteral("type")).toString().isEmpty()) {
            result.append(item);
        }
    }
    return result;
}

QStringList schemaKeys(const QVariantList &schema)
{
    QStringList keys;
    for (const QVariant &item : schema) {
        const QString key = item.toMap().value(QStringLiteral("key")).toString();
        if (!key.isEmpty() && !keys.contains(key))
            keys.append(key);
    }
    return keys;
}

QVariantMap defaultConfig(const QVariantList &schema)
{
    QVariantMap config;
    for (const QVariant &item : schema) {
        const QVariantMap entry = item.toMap();
        const QString key = entry.value(QStringLiteral("key")).toString();
        if (!key.isEmpty() && entry.contains(QStringLiteral("default")))
            config.insert(key, entry.value(QStringLiteral("default")));
    }
    return config;
}

} // namespace WidgetSchema
