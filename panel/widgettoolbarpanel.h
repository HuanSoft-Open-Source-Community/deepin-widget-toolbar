// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <panel.h>

#include <DConfig>

#include <QEvent>
#include <QPointer>
#include <QTimer>

DS_USE_NAMESPACE
using Dtk::Core::DConfig;

class QQuickWindow;
class WidgetManager;
class WidgetListModel;

class WidgetToolbarPanel : public DPanel
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.widgettoolbar")
    Q_PROPERTY(bool visible READ visible WRITE setVisible NOTIFY visibleChanged FINAL)
    Q_PROPERTY(bool pinned READ pinned WRITE setPinned NOTIFY pinnedChanged FINAL)
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
    // 菜单动作信号（D-Bus ExportAllSignals 导出，QML Connections 监听）
    void settingsRequested();
    void aboutRequested();
    void addWidgetRequested();
    void autoArrangeRequested();

protected:
    // X11 下 LayerShellEmulation 的 LayerButtom 分支会用 setFlags() 整体替换窗口 flags
    // （清掉 Qt.Tool/Qt.FramelessWindowHint），且窗口重建后窗口类型属性丢失，都会让面板
    // 回落为普通窗口被 kwin 装饰出标题栏与窗口按钮。这里在窗口事件（显示/曝光/重建）
    // 与 layer 变化时强制恢复期望的 frameless flags，作为 QML 端 applyLayerFlags 的主兜底。
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void enforceFrameless();
    // X11 下按当前边距短轮询校准窗口几何，覆盖 hide/show 重建、screen 迟到等
    // 事件错位场景（约 5s 后自动停止）；Wayland 不启动。
    QTimer m_geometryTimer;
    int m_geometryTicks = 0;
    // QPointer：窗口可能在 hide/show 或屏幕变更时被重建销毁，避免裸指针悬垂
    QPointer<QQuickWindow> m_window;

    DConfig *m_config = nullptr;
    bool m_visible = true;
    bool m_pinned = true;

    WidgetManager *m_widgetManager = nullptr;
    WidgetListModel *m_widgetListModel = nullptr;
};
