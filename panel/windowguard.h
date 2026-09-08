// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QTimer>

#include <xcb/xcb.h>

class QQuickWindow;

// 面板窗口的层级与几何守护（从 WidgetToolbarPanel 拆分）：
// X11 下 LayerShellEmulation 的 LayerButtom 分支会用 setFlags() 整体替换窗口
// flags（清掉 Qt.Tool 等），且窗口 hide/show 重建后模拟层不重跑，都会让面板
// 回落为普通窗口/类型丢失。本类在窗口事件（显示/曝光/重建）与 layer 变化时
// 强制恢复期望的 flags 与手动窗口类型（详见下方说明），并短轮询校准窗口
// 几何。Wayland 下全部为无操作。
//
// 窗口类型兜底：在 QWindow 上设置 Qt 私有手动类型属性
// （"_q_xcb_wm_window_type"，QXcbWindow::setWindowFlags 读取；置顶=Notification
// 0x800、置底=Dock 0x4），使 Qt 在每次平台窗口创建与每次 setFlags 时、映射之前
// 写入正确类型——LayerShellEmulation 只在 DLayerShellWindow 创建/layer 变化时写
// 一次，hide/show 重建窗口后不重跑，且 flags 派生类型（UTILITY+NORMAL）会覆盖它。
// 同时 flags 刻意不含 Qt::FramelessWindowHint：Qt 对 Frameless 窗口写的
// _MOTIF_WM_HINTS 无 MWM_HINTS_FUNCTIONS 位，kwin 判定可最大化，首次映射高度
// 达到工作区时被垂直最大化（上下边距为 0）并被钉住；改加 Min/Close 按钮 hint
// 后 Qt 写出带 Functions 位、不含 Maximize 的白名单，kwin 判定不可最大化，
// 从根源阻止拉伸（X11Window::manage 的尺寸判定不再触发）。
class WindowGuard : public QObject
{
    Q_OBJECT
public:
    explicit WindowGuard(QObject *parent = nullptr);

    // 绑定（或重新绑定）窗口：安装事件过滤器并监听 layer/边距变化；
    // 窗口 hide/show 或屏幕变更重建后由宿主再次调用
    void attach(QQuickWindow *window);
    // 同步面板置顶状态（决定恢复的 flags）
    void setPinned(bool pinned);

    // 请求面板窗口获得 OS 键盘焦点（便签等文本小组件点击进入编辑时经
    // WidgetHost 调用）。X11 下 kwin 不因点击激活 Dock/Notification 类面板窗，
    // 仅 QML 取焦时光标会闪但按键到不了窗口；这里先 requestActivate()
    // （_NET_ACTIVE_WINDOW，带最近用户交互时间戳），仍未激活则延迟直设
    // X 输入焦点兜底。Wayland 下 requestActivate 无副作用，直接返回。
    static void ensureKeyboardFocus(QQuickWindow *window);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void enforceFrameless();
    // 恢复 X11 窗口类型（_NET_WM_WINDOW_TYPE）：setFlags 会按 Qt.Tool 重算为
    // UTILITY+NORMAL，kwin 会对含 NORMAL 的窗口执行 placement（垂直最大化），
    // 面板首次打开上下边距为 0。这里按 pinned 恢复为 Notification/Dock。
    void enforceWindowType();
    // 显式声明 _MOTIF_WM_HINTS（functions 白名单仅含 Move|Resize，不含 Maximize）：
    // kwin 在窗口首次管理时按 motif 判定 isMaximizable()，无 functions 标志时默认
    // 允许最大化；显式白名单让 kwin 判定不可最大化，从根源上阻止自动最大化。
    void enforceMotifHints();

    QQuickWindow *m_window = nullptr;
    bool m_pinned = true;
    // 缓存的 X11 原子：窗口类型属性与两个面板类型值（首次使用时 intern）
    xcb_atom_t m_wmTypeAtom = 0;
    xcb_atom_t m_notificationAtom = 0;
    xcb_atom_t m_dockAtom = 0;
    xcb_atom_t m_normalAtom = 0;
    // 缓存的 X11 原子：_MOTIF_WM_HINTS（enforceMotifHints 使用）
    xcb_atom_t m_motifHintsAtom = 0;
    // X11 下按当前边距短轮询校准窗口几何，覆盖 hide/show 重建、screen 迟到等
    // 事件错位场景（约 5s 后自动停止）；Wayland 不启动。
    QTimer m_geometryTimer;
    int m_geometryTicks = 0;
};
