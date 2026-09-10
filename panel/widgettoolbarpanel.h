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
class PanelAvoidWatcher;
class DesktopApps;
class QQuickWindow;
class QQmlEngine;

class WidgetToolbarPanel : public DPanel
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.widgettoolbar")
    Q_PROPERTY(bool visible READ visible WRITE setVisible NOTIFY visibleChanged FINAL)
    Q_PROPERTY(bool pinned READ pinned WRITE setPinned NOTIFY pinnedChanged FINAL)
    // 面板级"卡片透明模式"：全局卡片底半透明叠层，与小组件自身 transparentBackground 解耦
    Q_PROPERTY(bool cardTransparent READ cardTransparent WRITE setCardTransparent NOTIFY cardTransparentChanged FINAL)
    // 面板级"卡片名称显示"：在每张卡片下方显示小组件本地化名称。**仅全局生效**，
    // 刻意不提供任何按实例的读写接口；开启时卡片等比缩小让出名称空间（长宽比不变）。
    Q_PROPERTY(bool showCardNames READ showCardNames WRITE setShowCardNames NOTIFY showCardNamesChanged FINAL)
    // 多任务视图（MMV）避让运行时状态：true 时面板窗口临时隐藏。仅由 kwin 的
    // MultitaskStateChanged 信号驱动，不持久化，也不改变 visible/托盘高亮；
    // MMV 退出后绑定表达式自动恢复面板显示
    Q_PROPERTY(bool multitaskAvoided READ multitaskAvoided NOTIFY multitaskAvoidedChanged FINAL)
    // 外部面板避让运行时状态：通知/通知中心/控制中心/电源/剪贴板/托盘快捷
    // 面板与展开小卡等**几何与本侧栏叠合**期间为 true，侧栏据此临时隐藏，
    // 其关闭或移开自动恢复（展开在侧栏之外的小卡不触发，几何不可知时退化为
    // 照旧避让）。与 multitaskAvoided 独立并列（任一为真即隐藏），仅 X11 平台
    // 生效，不持久化、不改变 visible/托盘高亮。由 PanelAvoidWatcher 驱动。
    Q_PROPERTY(bool panelAvoided READ panelAvoided NOTIFY panelAvoidedChanged FINAL)
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
    bool showCardNames() const;
    void setShowCardNames(bool showCardNames);
    bool multitaskAvoided() const;
    bool panelAvoided() const;

    WidgetManager *widgetManager() const;
    WidgetListModel *widgetListModel() const;

    // 当前小组件宿主窗口（rootObject 即 QML 主窗口）；小组件请求键盘
    // 输入（便签文本编辑等）时用于激活窗口，rootObject 未就绪返回 nullptr
    QQuickWindow *rootWindow() const;

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
    void showCardNamesChanged(bool showCardNames);
    void multitaskAvoidedChanged(bool multitaskAvoided);
    void panelAvoidedChanged(bool panelAvoided);
    // 菜单动作信号（D-Bus ExportAllSignals 导出，QML Connections 监听）
    void settingsRequested();
    void aboutRequested();
    void addWidgetRequested();
    void autoArrangeRequested();

private Q_SLOTS:
    // kwin 特效 MultitaskStateChanged(bool) 信号回调（D-Bus 字符串式连接，
    // 与 dde-shell DockHelper 同款）：进入 MMV 置避让、退出清避让
    void onMultitaskStateChanged(bool active);

private:
    // MMV 避让状态写入：仅供信号回调使用（QML 端只读该属性）。
    void setMultitaskAvoided(bool avoided);
    // 订阅 kwin 的 MultitaskStateChanged 信号，并异步对账初始 MMV 状态
    void watchMultitaskView();

    // X11 窗口层级与几何守护（enforceFrameless/事件过滤/几何轮询）已拆分到 WindowGuard
    WindowGuard *m_windowGuard = nullptr;
    // 外部面板避让监视器（X11）：panelAvoided 属性即其 avoided 转发，
    // 信号对信号连接，无本地副本；面板自身窗口经 rootObjectChanged 一并
    // attachPanel 给它做几何叠合判定（窗口重建后重新绑定）
    PanelAvoidWatcher *m_panelAvoidWatcher = nullptr;
    DConfig *m_config = nullptr;
    bool m_visible = true;
    bool m_pinned = true;
    bool m_cardTransparent = false;
    // 卡片名称显示：默认开启（功能本身即"显示名称"，默认关会让人以为不存在）
    bool m_showCardNames = true;
    bool m_multitaskAvoided = false;

    WidgetManager *m_widgetManager = nullptr;
    WidgetListModel *m_widgetListModel = nullptr;
    // 应用图标 image provider 已注册的 QML 引擎（rootObject 重建时防重复注册）
    QQmlEngine *m_iconEngine = nullptr;
};
