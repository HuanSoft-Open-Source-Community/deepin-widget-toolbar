// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <panel.h>

#include <DConfig>

#include <QPointer>

DS_USE_NAMESPACE
using Dtk::Core::DConfig;

class WidgetManager;
class WidgetListModel;
class WindowGuard;

class WidgetToolbarPanel : public DPanel
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.widgettoolbar")
    Q_PROPERTY(bool visible READ visible WRITE setVisible NOTIFY visibleChanged FINAL)
    Q_PROPERTY(bool pinned READ pinned WRITE setPinned NOTIFY pinnedChanged FINAL)
    // 面板级"卡片透明模式"：全局卡片底半透明叠层，与小组件自身 transparentBackground 解耦
    Q_PROPERTY(bool cardTransparent READ cardTransparent WRITE setCardTransparent NOTIFY cardTransparentChanged FINAL)
    // 小组件宿主接口：QML 通过 Panel.widgetManager / Panel.widgetListModel 访问
    Q_PROPERTY(WidgetManager *widgetManager READ widgetManager CONSTANT)
    Q_PROPERTY(WidgetListModel *widgetListModel READ widgetListModel CONSTANT)
public:
    explicit WidgetToolbarPanel(QObject *parent = nullptr);
    ~WidgetToolbarPanel() override;

    bool load() override;
    bool init() override;

    bool visible() const;
    void setVisible(bool visible);
    bool pinned() const;
    void setPinned(bool pinned);
    bool cardTransparent() const;
    void setCardTransparent(bool cardTransparent);

    WidgetManager *widgetManager() const;
    WidgetListModel *widgetListModel() const;

public Q_SLOTS:
    // 供 D-Bus（org.deepin.dde.widgettoolbar）与 QML 调用的显隐控制
    void toggle();
    void show();
    void hide();
    // 右键菜单动作：托盘插件经 D-Bus 调用，QML 监听对应信号执行 UI
    void openSettings();
    void showAbout();
    void openAddWidget();
    void autoArrange();

Q_SIGNALS:
    void visibleChanged(bool visible);
    void pinnedChanged(bool pinned);
    void cardTransparentChanged(bool cardTransparent);
    // 菜单动作信号（D-Bus ExportAllSignals 导出，QML Connections 监听）
    void settingsRequested();
    void aboutRequested();
    void addWidgetRequested();
    void autoArrangeRequested();

private:
    // X11 窗口层级与几何守护（enforceFrameless/事件过滤/几何轮询）已拆分到 WindowGuard
    WindowGuard *m_windowGuard = nullptr;
    DConfig *m_config = nullptr;
    bool m_visible = true;
    bool m_pinned = true;
    bool m_cardTransparent = false;

    WidgetManager *m_widgetManager = nullptr;
    WidgetListModel *m_widgetListModel = nullptr;
};
