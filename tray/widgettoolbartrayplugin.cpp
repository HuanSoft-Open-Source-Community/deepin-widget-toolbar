// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbartrayplugin.h"

#include "traybutton.h"

#include <QCoreApplication>
#include <QDebug>
#include <QLocale>
#include <QTranslator>

WidgetToolbarTrayPlugin::WidgetToolbarTrayPlugin(QObject *parent)
    : QObject(parent)
{
}

WidgetToolbarTrayPlugin::~WidgetToolbarTrayPlugin()
{
    if (m_proxyInter) {
        m_proxyInter->itemRemoved(this, pluginName());
    }
    delete m_button;
}

const QString WidgetToolbarTrayPlugin::pluginName() const
{
    return QStringLiteral("widget-toolbar");
}

const QString WidgetToolbarTrayPlugin::pluginDisplayName() const
{
    return tr("Widget Toolbar");
}

void WidgetToolbarTrayPlugin::init(PluginProxyInterface *proxyInter)
{
    m_proxyInter = proxyInter;
    loadTranslator();

    if (!m_button) {
        m_button = new TrayButton;
        m_button->initDbus();
    }
    m_proxyInter->itemAdded(this, pluginName());
}

QWidget *WidgetToolbarTrayPlugin::itemWidget(const QString &itemKey)
{
    Q_UNUSED(itemKey)
    return m_button;
}

QWidget *WidgetToolbarTrayPlugin::itemTipsWidget(const QString &itemKey)
{
    Q_UNUSED(itemKey)
    return nullptr;
}

QWidget *WidgetToolbarTrayPlugin::itemPopupApplet(const QString &itemKey)
{
    Q_UNUSED(itemKey)
    return nullptr;
}

Dock::PluginFlags WidgetToolbarTrayPlugin::flags() const
{
    // 基础托盘插件：不附加拖拽/控制中心设置等无关能力
    return Dock::Type_Tray;
}

void WidgetToolbarTrayPlugin::loadTranslator()
{
    // dde-dock 不会自动加载第三方插件的翻译文件，需插件自行加载
    QTranslator *translator = new QTranslator(this);
    const QString locale = QLocale::system().name();
    const QString baseName = QStringLiteral("widget-toolbar_%1").arg(locale);
    if (translator->load(baseName, QStringLiteral("/usr/share/widget-toolbar/translations"))) {
        QCoreApplication::installTranslator(translator);
    } else {
        delete translator;
    }
}
