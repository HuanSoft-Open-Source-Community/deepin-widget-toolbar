// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbartrayplugin.h"

#include "traybutton.h"

#include <QCoreApplication>
#include <QDBusInterface>
#include <QDebug>
#include <QIcon>
#include <QJsonDocument>
#include <QLocale>
#include <QTranslator>

namespace {
// 与 TrayButton 保持一致的面板 D-Bus 服务
const QString kPanelService = QStringLiteral("org.deepin.dde.widgettoolbar");
const QString kPanelPath = QStringLiteral("/org/deepin/dde/widgettoolbar");
const QString kPanelInterface = QStringLiteral("org.deepin.dde.widgettoolbar");
}

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
    // 声明 Attribute_CanSetting 使插件出现在控制中心
    // "个性化 → 桌面和任务栏 → 插件区域"，可管理显示/隐藏；
    // 不附加拖拽能力，也不使用 Attribute_ForceDock（强制显示会从列表隐藏）
    return Dock::Type_Tray | Dock::Attribute_CanSetting;
}

QIcon WidgetToolbarTrayPlugin::icon(Dock::IconType dockPart, Dock::ThemeType themeType) const
{
    Q_UNUSED(dockPart)
    // 与任务栏按钮一致：暗色主题用白色版，亮色主题用黑色版
    return QIcon(themeType == Dock::ThemeType_Dark
                     ? QStringLiteral(":/widget-toolbar/widget-toolbar.svg")
                     : QStringLiteral(":/widget-toolbar/widget-toolbar-dark.svg"));
}

const QString WidgetToolbarTrayPlugin::itemContextMenu(const QString &itemKey)
{
    Q_UNUSED(itemKey)

    QList<QVariant> items;
    const auto makeItem = [](const QString &itemId, const QString &itemText) {
        QVariantMap action;
        action.insert("itemId", itemId);
        action.insert("itemText", itemText);
        action.insert("isCheckable", false);
        action.insert("isActive", true);
        return QVariant(action);
    };
    items.append(makeItem("open-settings", tr("Settings")));
    items.append(makeItem("show-about", tr("About")));
    items.append(makeItem("add-widget", tr("Add widget")));
    items.append(makeItem("auto-arrange", tr("Arrange")));

    QVariantMap menu;
    menu.insert("items", items);
    menu.insert("checkableMenu", false);
    menu.insert("singleCheck", false);
    return QString::fromUtf8(QJsonDocument::fromVariant(menu).toJson(QJsonDocument::Compact));
}

void WidgetToolbarTrayPlugin::invokedMenuItem(const QString &itemKey, const QString &menuId, const bool checked)
{
    Q_UNUSED(itemKey)
    Q_UNUSED(checked)

    QString method;
    if (menuId == QLatin1String("open-settings"))
        method = QStringLiteral("openSettings");
    else if (menuId == QLatin1String("show-about"))
        method = QStringLiteral("showAbout");
    else if (menuId == QLatin1String("add-widget"))
        method = QStringLiteral("openAddWidget");
    else if (menuId == QLatin1String("auto-arrange"))
        method = QStringLiteral("autoArrange");

    if (method.isEmpty()) {
        qWarning() << "widget-toolbar: unknown menu item" << menuId;
        return;
    }

    QDBusInterface iface(kPanelService, kPanelPath, kPanelInterface);
    if (!iface.isValid()) {
        qWarning() << "widget-toolbar D-Bus interface invalid";
        return;
    }
    iface.call(method);
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
