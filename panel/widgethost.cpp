// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgethost.h"

#include "widgetmanager.h"
#include "widgettoolbarpanel.h"
#include "windowguard.h"

#include <QDebug>
#include <QQuickWindow>

WidgetHost::WidgetHost(WidgetManager *manager, QObject *parent)
    : QObject(parent)
    , m_manager(manager)
{
}

bool WidgetHost::saveConfig(const QString &instanceId, const QVariantMap &values)
{
    if (!m_manager)
        return false;
    return m_manager->saveInstanceConfig(instanceId, values);
}

QStringList WidgetHost::usedZones(const QString &excludingInstanceId)
{
    if (!m_manager)
        return QStringList();
    return m_manager->usedZones(excludingInstanceId);
}

void WidgetHost::activateWindow()
{
    // 契约：宿主单例必须以面板为 parent（widgettoolbarpanel.cpp 注册时如此传入），
    // 面板窗口由它取出交给 WindowGuard 直设 X 输入焦点。若将来改挂到别的 parent，
    // 这里会取不到面板——静默返回会让"便签点了却打不进字"变得无从下手，故告警。
    auto *panel = qobject_cast<WidgetToolbarPanel *>(parent());
    if (!panel) {
        qWarning() << "WidgetHost::activateWindow: parent is not WidgetToolbarPanel;"
                   << "keyboard focus request dropped (check the singleton registration)";
        return;
    }
    WindowGuard::ensureKeyboardFocus(panel->rootWindow());
}

void WidgetHost::requestOpenAppPicker(const QString &instanceId, int index)
{
    Q_EMIT openAppPickerRequested(instanceId, index);
}
