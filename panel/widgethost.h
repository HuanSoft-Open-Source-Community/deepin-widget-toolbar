// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class WidgetManager;

// 小组件宿主能力代理（QML 单例 org.deepin.widgettoolbar/WidgetHost）：
// 小组件自身无法直接访问 WidgetManager，经本代理回写自身实例配置。
// 当前仅暴露保存配置一项能力，供世界时间等在运行期（如缩放补位）持久化设置。
class WidgetHost : public QObject
{
    Q_OBJECT
public:
    explicit WidgetHost(WidgetManager *manager, QObject *parent = nullptr);

    // 保存该实例的配置；仅允许 manifest settings schema 中声明的 key
    Q_INVOKABLE bool saveConfig(const QString &instanceId, const QVariantMap &values);
    // 其它实例 dials 中已使用的时区 id（世界时间跨实例地区唯一性用）
    Q_INVOKABLE QStringList usedZones(const QString &excludingInstanceId);

private:
    WidgetManager *m_manager = nullptr;
};
