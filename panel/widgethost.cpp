// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgethost.h"

#include "widgetmanager.h"
#include "widgettoolbarpanel.h"
#include "windowguard.h"

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
    auto *panel = qobject_cast<WidgetToolbarPanel *>(parent());
    if (!panel)
        return;
    WindowGuard::ensureKeyboardFocus(panel->rootWindow());
}

void WidgetHost::requestOpenAppPicker(const QString &instanceId, int index)
{
    Q_EMIT openAppPickerRequested(instanceId, index);
}
