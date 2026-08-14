// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "pluginsiteminterface_v2.h"

#include <QObject>

class TrayButton;

// dde-dock 托盘区触发按钮插件（dde-tray-loader 2.0.38，V2 接口）
// 通过 D-Bus 控制 dde-shell 侧栏面板（org.deepin.ds.widgettoolbar）显隐
class WidgetToolbarTrayPlugin : public QObject, public PluginsItemInterfaceV2
{
    Q_OBJECT
    Q_INTERFACES(PluginsItemInterfaceV2)
    Q_PLUGIN_METADATA(IID ModuleInterface_iid_V2 FILE "metadata.json")
public:
    explicit WidgetToolbarTrayPlugin(QObject *parent = nullptr);
    ~WidgetToolbarTrayPlugin() override;

    const QString pluginName() const override;
    const QString pluginDisplayName() const override;
    void init(PluginProxyInterface *proxyInter) override;
    QWidget *itemWidget(const QString &itemKey) override;
    QWidget *itemTipsWidget(const QString &itemKey) override;
    QWidget *itemPopupApplet(const QString &itemKey) override;
    Dock::PluginFlags flags() const override;
    // 控制中心"个性化 → 桌面和任务栏 → 插件区域"显示图标
    QIcon icon(Dock::IconType dockPart, Dock::ThemeType themeType) const override;
    // 右键菜单：设置 / 关于 / 添加组件 / 一键自动整理（JSON 协议）
    const QString itemContextMenu(const QString &itemKey) override;
    void invokedMenuItem(const QString &itemKey, const QString &menuId, const bool checked) override;

private:
    void loadTranslator();

private:
    PluginProxyInterface *m_proxyInter = nullptr;
    TrayButton *m_button = nullptr;
};
