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
// 当前暴露保存配置与键盘焦点请求两项能力。
class WidgetHost : public QObject
{
    Q_OBJECT
public:
    explicit WidgetHost(WidgetManager *manager, QObject *parent = nullptr);

    // 保存该实例的配置；仅允许 manifest settings schema 中声明的 key
    Q_INVOKABLE bool saveConfig(const QString &instanceId, const QVariantMap &values);
    // 其它实例 dials 中已使用的时区 id（世界时间跨实例地区唯一性用）
    Q_INVOKABLE QStringList usedZones(const QString &excludingInstanceId);
    // 小组件点击进入文本编辑（如便签）时请求 OS 键盘焦点：
    // X11 下面板是 Dock/Notification 类窗口，kwin 不因点击授予键盘焦点，
    // 只做 QML 取焦光标会闪但按键无法送达；详见 WindowGuard::ensureKeyboardFocus
    Q_INVOKABLE void activateWindow();

private:
    WidgetManager *m_manager = nullptr;
};
