// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QLoggingCategory>
#include <QObject>
#include <QHash>
#include <QPointer>
#include <QRect>

#include <xcb/xcb.h>

QT_BEGIN_NAMESPACE
class QSocketNotifier;
class QWindow;
QT_END_NAMESPACE

Q_DECLARE_LOGGING_CATEGORY(panelAvoidLog)

// 侧栏面板避让监视器（X11）：跟踪通知弹出、通知中心、控制中心、电源、
// 剪贴板、托盘快捷面板/展开小卡等面板窗口的映射状态，任一同本侧栏几何叠合
// 者在场即置 avoided——侧栏据此临时隐藏（与多任务视图避让同款语义），面板
// 关闭自动恢复。仅 X11 平台生效（Wayland 无跨客户窗口事件流，start 后保持
// 静默，avoided 恒 false）。
//
// 窗口身份（实测 xwininfo：dde-shell 各包共享 WM_CLASS "dde-shell"，以
// WM_NAME 区分；独立应用以 WM_CLASS 区分）：
//   标题精确：org.deepin.ds.notificationbubble（通知弹出）
//             org.deepin.ds.notificationcenter（通知中心）
//             org.deepin.ds.dde-shutdown（电源/注销对话框）
//   标题前缀：dde-shell/panelpopup（托盘快捷面板宿主窗，任何尺寸皆可能避让）
//             dde-shell/paneltooltip（托盘展开小卡与悬停提示共用宿主窗，
//               映射尺寸达小卡阈值才可能避让，悬停 tooltip 不触发）
//   类名精确：dde-control-center / dde-clipboard
// 以上任一命中后仍需与本侧栏矩形叠合（见下方"几何叠合判定"）才真正避让。
// 本面板自身窗口（org.deepin.ds.widgettoolbar / dde-shell/widgettoolbar*）
// 永不匹配，防自触发。新映射窗口一律 qCDebug 记录，未列面板据日志补集。
//
// 身份命中后还要过几何叠合判定：目标窗 root 绝对矩形与本面板 root 绝对矩形
// 相交（含 kAvoidPad 边距）才算冲突、才置 avoided；展开在侧栏之外的小卡/快捷
// 面板位置不冲突，无需避让。任一侧几何不可知（自身矩形未知、translate 失败、
// 尺寸非法）一律退化为"冲突"，宁可多避一次不可漏避。
// DPI 折算用本面板所在屏的 devicePixelRatio（QWindow 几何为 DIP，X11 为像素）：
// 单屏或各屏同缩放时精确，混合 DPR 多屏存在原点误差（此时最坏退化为误判叠合，
// 由目标窗 ConfigureNotify 与本面板位置/尺寸变化事件重估自我收敛）。
class PanelAvoidWatcher : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool avoided READ avoided NOTIFY avoidedChanged FINAL)
public:
    explicit PanelAvoidWatcher(QObject *parent = nullptr);
    ~PanelAvoidWatcher() override;

    bool avoided() const { return m_avoided; }

    // 仅 xcb 平台生效：独立连接订阅 root SubstructureNotify，并做启动
    // 对账（宿主可能在目标面板已开时才启动，错过 MapNotify）
    void start();

    // 注入侧栏自身窗口，用于几何叠合判定：面板矩形（root 像素坐标）由
    // QWindow 全局位置 × 本屏 DPR 折算，并监听 x/y/width/heightChanged、
    // screenChanged、visibilityChanged 重估全部窗口（侧栏改宽、换屏、首次
    // 映射后自愈）。窗口 hide/show 重建后由宿主再次调用（与 WindowGuard::attach
    // 同一时机）；传 nullptr 解除绑定。
    void attachPanel(QWindow *panel);

Q_SIGNALS:
    void avoidedChanged(bool avoided);

private:
    struct WinInfo {
        QString name;       // WM_NAME
        QString resName;    // WM_CLASS res_name
        QString className;  // WM_CLASS res_class
        int width = 0;
        int height = 0;
        // root 绝对坐标（像素）；hasPos=false 表示尚未读到
        int rootX = 0;
        int rootY = 0;
        bool hasPos = false;
        bool mapped = false;
        bool counted = false;
    };

    void onEvents();
    void handleEvent(xcb_generic_event_t *event);
    // 同步拉取标题/类名/几何（本地 socket 单次往返，映射事件低频）
    void fetchIdentity(xcb_window_t win, WinInfo &info);
    // 同步拉取该窗在 root 上的绝对左上角（translate_coordinates，含 reparent 偏移）
    void fetchRootPosition(xcb_window_t win, WinInfo &info);
    // 对该窗自身订阅 StructureNotify+PropertyChange：被 WM reparent 进
    // 装饰框后，root 不再收到其 Map/Unmap，唯有直接订阅才能继续跟踪
    void selectEvents(xcb_window_t win);
    bool isTarget(const WinInfo &info) const;
    // 本面板 root 绝对矩形（像素）：不可知时返回空 QRect
    QRect panelRect() const;
    // 目标窗是否与本面板矩形叠合（几何不可知时退化为 true=照旧避让）
    bool conflictsWithPanel(const WinInfo &info) const;
    // 重估全部在册窗口（面板矩形变化时用）
    void reevaluateAll();
    // 依 mapped + 目标判定 + 叠合判定翻转 counted，并刷新聚合状态
    void evaluate(xcb_window_t win);
    void refreshAvoided();
    void setAvoided(bool avoided);
    // 启动对账：递归遍历 root 子树（含 WM 装饰框下一层），已映射者建档
    void reconcileInitial();
    void reconcileWindow(xcb_window_t win, int depth);

    xcb_connection_t *m_conn = nullptr;
    xcb_window_t m_root = 0;
    QSocketNotifier *m_notifier = nullptr;
    QHash<xcb_window_t, WinInfo> m_windows;
    // 侧栏自身窗口与其最近一次有效矩形（root 像素）：窗口未映射/未 exposed
    // 期间（含正在避让时）用缓存值判定叠合，故缓存由 const 访问器惰性写入
    QPointer<QWindow> m_panel;
    mutable QRect m_panelRectCached;
    bool m_avoided = false;
};
