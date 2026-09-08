// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "windowguard.h"

#include <dlayershellwindow.h>
#include <dsglobal.h>

DS_USE_NAMESPACE

// 与 main.qml 的 contentPadding 保持一致：三条 layer-shell 边距的下限。
// 边距任何时刻都不应为 0（0 会让面板在首次映射时被拉满全高）。
static constexpr int kDefaultMargin = 10;

#include <QDebug>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQuickWindow>
#include <QScreen>

#include <cstring>

WindowGuard::WindowGuard(QObject *parent)
    : QObject(parent)
{
    // X11 下短轮询校准窗口几何：边距/屏幕数据就绪时机不稳定，事件钩子可能错过，
    // 按当前边距重算期望几何，与实际不符即修正（约 5s 后自动停止）。
    m_geometryTimer.setInterval(250);
    m_geometryTimer.setSingleShot(false);
    connect(&m_geometryTimer, &QTimer::timeout, this, [this]() {
        if (QGuiApplication::platformName() != "xcb") {
            m_geometryTimer.stop();
            return;
        }
        enforceFrameless();
        // 窗口首次映射后若边距/屏幕数据尚未定型，kwin 的 manage 可能按映射时
        // 几何做过 placement，此处持续校准直到稳定（修复后窗口不会被最大化，
        // 纠正均被 kwin 接受，一两个 tick 即收敛）。
        if (++m_geometryTicks > 40)
            m_geometryTimer.stop();
    });
}

void WindowGuard::attach(QQuickWindow *window)
{
    if (!window || window == m_window)
        return;
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = window;
    m_window->installEventFilter(this);
    if (auto *shell = DLayerShellWindow::get(m_window)) {
        connect(shell, &DLayerShellWindow::layerChanged, this, &WindowGuard::enforceFrameless);
        // X11 下边距由 0 变为正确值后，模拟层可能不按最新边距重放窗口几何，
        // 这里监听边距变化直接重算锚定几何（enforceFrameless 内部仅 xcb 生效）。
        connect(shell, &DLayerShellWindow::marginsChanged, this, &WindowGuard::enforceFrameless);
        // QML 端的边距绑定在组件完成阶段才求值，而本 attach()（rootObjectChanged 时触发）
        // 早于该阶段：窗口首次映射前若边距仍为 0，模拟层/几何守护会以 0 边距计算几何，
        // 面板被拉满全高（首次打开时上下边距为 0）。这里先按 contentPadding（main.qml 中
        // 的常量，现为 10，如修改需同步）下限补齐，任何求值顺序下都不会出现 0 边距。
        if (shell->topMargin() == 0)
            shell->setTopMargin(kDefaultMargin);
        if (shell->rightMargin() == 0)
            shell->setRightMargin(kDefaultMargin);
        if (shell->bottomMargin() == 0)
            shell->setBottomMargin(kDefaultMargin);
    }
    enforceFrameless();
    m_geometryTicks = 0;
    m_geometryTimer.start();
}

void WindowGuard::setPinned(bool pinned)
{
    if (m_pinned == pinned)
        return;
    m_pinned = pinned;
    enforceFrameless();
}

// 小组件点击进入文本编辑时的键盘焦点请求（见头文件注释）。
void WindowGuard::ensureKeyboardFocus(QQuickWindow *window)
{
    if (!window)
        return;
    // X11：requestActivate() 向 kwin 发送 _NET_ACTIVE_WINDOW（Qt 附带最近一次
    // 用户交互的时间戳，kwin 视为用户手势放行激活）。
    window->requestActivate();
    if (QGuiApplication::platformName() != "xcb")
        return; // Wayland：layer-shell OnDemand 表面由合成器在点击时授予键盘
    // kwin 对 Dock/Notification 等面板类型可能仍拒绝激活；延迟后确认窗口
    // 仍未激活则直设 X 输入焦点兜底（与 xdotool windowfocus 同路径，kwin
    // 接受；触发前提是用户刚在本窗口内点击，不会凭空抢焦点）。
    QTimer::singleShot(250, window, [window]() {
        if (window->isActive() || QGuiApplication::platformName() != "xcb")
            return;
        auto *x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
        if (!x11App || !x11App->connection() || !window->handle())
            return;
        xcb_set_input_focus(x11App->connection(), XCB_INPUT_FOCUS_PARENT,
                            window->winId(), XCB_CURRENT_TIME);
    });
}

// 期望 flags 与 QML 端 applyLayerFlags 保持一致：置顶时 WindowStaysOnTopHint，
// 置底时 WindowStaysOnBottomHint。仅在 xcb 平台需要（Wayland 下 layer-shell
// 窗口由合成器管理；X11 下 LayerShellEmulation 的 layer 映射在窗口 hide/show
// 重建原生窗口后不会重新应用，故层级完全由这里恢复的 flags 保证）。
// 注意 flags 刻意不含 Qt::FramelessWindowHint：Qt 对带 Frameless 的窗口写
// _MOTIF_WM_HINTS 时（setMotifWmHints）不置 MWM_HINTS_FUNCTIONS 位、functions
// 恒为 MWM_FUNC_ALL，kwin 的 MotifHints::testFunction() 对无 Functions 位的属性
// 返回"全部功能允许"，isMaximizable()=true——首次映射高度达到工作区时被 kwin
// 垂直最大化（y=0、上下边距为 0）并被钉住（configureRequest 拒绝、合成
// ConfigureNotify 回拉）。Min/Close 按钮 hint（无 Maximize）让 Qt 写出
// functions=MOVE|RESIZE|MINIMIZE|CLOSE 且带 Functions 位，kwin 判定不可最大化。
void WindowGuard::enforceFrameless()
{
    if (!m_window || QGuiApplication::platformName() != "xcb") {
        return;
    }
    // 手动窗口类型（Qt 私有扩展点）：QXcbWindow::setWindowFlags → setWmWindowType
    // 读取该动态属性（qxcbwindow.cpp setWindowFlags 内 dynamicPropertyNames 检查），
    // 在每次平台窗口创建（含 hide/show 重建）与每次 setFlags 时、映射之前写入
    // _NET_WM_WINDOW_TYPE=[类型, UTILITY, NORMAL]；值域为 QXcbWindow::WindowType
    // 位掩码（私有头文件，值取自 Qt 6.8 源码）：Notification=0x800、Dock=0x4。
    // 这使重建窗口的映射前类型恒定正确（kwin 对 Notification 走 placeOnScreenDisplay
    // 仅移动、对 Dock 直接跳过 placement），且不被 flags 派生的类型覆盖；
    // 置底时还需覆盖 LayerShellEmulation 在 LayerButtom 分支写入的 Normal 手动类型。
    m_window->setProperty("_q_xcb_wm_window_type",
                          static_cast<int>(m_pinned ? 0x800 : 0x4));
    Qt::WindowFlags desired = Qt::Tool
        | Qt::WindowMinimizeButtonHint | Qt::WindowCloseButtonHint;
    desired |= m_pinned ? Qt::WindowStaysOnTopHint : Qt::WindowStaysOnBottomHint;
    if (m_window->flags() != desired) {
        m_window->setFlags(desired);
    }
    // QWindow::setFlags() 会触发 QXcbWindow 按 flags 重算 _NET_WM_WINDOW_TYPE
    // （Qt.Tool → UTILITY + NORMAL），覆盖 LayerShellEmulation 按 layer 设置的
    // 类型；QML 端 applyLayerFlags 也可能在任何时机 setFlags，因此这里无条件
    // 恢复面板类型（仅 xcb）。
    enforceWindowType();
    // kwin 在窗口首次管理（映射）时若窗口尺寸达到工作区大小会自动垂直最大化
    // （与窗口类型无关，实测 [NOTIFICATION, NORMAL] 类型同样被拉满全高）；显式
    // motif 白名单（不含 Maximize）让 kwin 判定不可最大化，从根源阻止。
    // 注意：这里的写发生在映射之后（SurfaceCreated 为异步事件），kwin 的 manage
    // 判定不可见；真正在映射前生效的是 Qt 侧写入（本函数开头 setFlags 触发的
    // setMotifWmHints，由 main.qml/本函数的 flags 组合保证），此处仅作双保险。
    enforceMotifHints();
    // 兜底：X11 LayerShellEmulation 的 onPositionChanged 依赖 QWindow::screen()
    // 与 marginsChanged 时序，窗口 hide/show 重建后可能不按最新边距放置窗口
    // （实测 margins 正确但窗口几何停留在旧值）。这里按 main.qml 固定的
    // anchors（Right|Top|Bottom）+ DLayerShellWindow 当前边距直接计算并设置，
    // 与模拟器公式一致，只在窗口事件（显示/曝光/重建）时执行，无循环风险。
    if (auto *shell = DLayerShellWindow::get(m_window)) {
        if (QScreen *screen = m_window->screen()) {
            const QRect sg = screen->geometry();
            const int w = m_window->width();
            const int h = sg.height() - shell->topMargin() - shell->bottomMargin();
            const int x = sg.right() + 1 - w - shell->rightMargin();
            const int y = sg.top() + shell->topMargin();
            const QRect target(x, y, w, h);
            if (m_window->geometry() != target) {
                qWarning().noquote() << "widgettoolbar: correcting X11 geometry"
                    << m_window->geometry() << "->" << target
                    << "margins(top/right/bottom):" << shell->topMargin()
                    << shell->rightMargin() << shell->bottomMargin()
                    << "screen:" << sg;
                m_window->setGeometry(target);
            }
        }
    }
}

// 恢复 X11 窗口类型（_NET_WM_WINDOW_TYPE）：
// LayerShellEmulation 按 layer 设置的类型（Overlay→Notification/Buttom→Normal/
// Top→Dock）会被 QWindow::setFlags() 重算的类型（UTILITY+NORMAL）覆盖，kwin
// 对含 NORMAL 的窗口执行 placement（本机为垂直最大化），面板首次打开时上下
// 边距为 0（y=0、高度=工作区高度）。这里按 pinned 状态直接以 xcb_change_property
// 整体替换类型列表（置顶=Notification、置底=Dock），kwin 将面板识别为面板窗口
// 而非普通窗口，不再最大化。仅在 xcb 平台生效，Wayland 下为无操作。
void WindowGuard::enforceWindowType()
{
    if (!m_window || !m_window->handle()
        || QGuiApplication::platformName() != "xcb") {
        return;
    }
    auto *x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    if (!x11App || !x11App->connection()) {
        return;
    }
    xcb_connection_t *conn = x11App->connection();

    // 惰性缓存原子：窗口类型属性与两个面板类型值（首次使用时 intern）
    auto ensureAtom = [conn](xcb_atom_t *slot, const char *name) {
        if (*slot != 0)
            return;
        xcb_intern_atom_cookie_t cookie = xcb_intern_atom(conn, 0, std::strlen(name), name);
        xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(conn, cookie, nullptr);
        if (reply) {
            *slot = reply->atom;
            free(reply);
        }
    };
    ensureAtom(&m_wmTypeAtom, "_NET_WM_WINDOW_TYPE");
    ensureAtom(&m_notificationAtom, "_NET_WM_WINDOW_TYPE_NOTIFICATION");
    ensureAtom(&m_dockAtom, "_NET_WM_WINDOW_TYPE_DOCK");
    ensureAtom(&m_normalAtom, "_NET_WM_WINDOW_TYPE_NORMAL");
    if (m_wmTypeAtom == 0) {
        return;
    }

    // 与 LayerShellEmulation 的 setWindowType 输出一致：主类型 + NORMAL 双元素
    // （通知中心窗口即 [NOTIFICATION, NORMAL]，实测 kwin 不做特殊放置）。
    const xcb_atom_t types[2] = {
        m_pinned ? m_notificationAtom : m_dockAtom,
        m_normalAtom
    };
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, m_window->winId(), m_wmTypeAtom,
                        XCB_ATOM_ATOM, 32, 2, types);
    xcb_flush(conn);
}

// 显式声明 _MOTIF_WM_HINTS：kwin 在 X11Window::manage 里按
// isMaximizable()（内部检查 Motif hints 的 maximize 功能）决定是否把
// "尺寸达到工作区"的新窗口自动最大化；Qt 对无边框窗口不写 functions
// 标志，kwin 视为"未限制"（允许最大化）。这里写入 functions 白名单
// （MWM_FUNC_MOVE | MWM_FUNC_RESIZE，不含 MWM_FUNC_MAXIMIZE），
// kwin 判定不可最大化，面板首次映射时不会被拉满工作区高度。
// 仅在 xcb 平台生效，Wayland 下为无操作。
void WindowGuard::enforceMotifHints()
{
    if (!m_window || !m_window->handle()
        || QGuiApplication::platformName() != "xcb") {
        return;
    }
    auto *x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    if (!x11App || !x11App->connection()) {
        return;
    }
    xcb_connection_t *conn = x11App->connection();

    auto ensureAtom = [conn](xcb_atom_t *slot, const char *name) {
        if (*slot != 0)
            return;
        xcb_intern_atom_cookie_t cookie = xcb_intern_atom(conn, 0, std::strlen(name), name);
        xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(conn, cookie, nullptr);
        if (reply) {
            *slot = reply->atom;
            free(reply);
        }
    };
    ensureAtom(&m_motifHintsAtom, "_MOTIF_WM_HINTS");
    if (m_motifHintsAtom == 0) {
        return;
    }

    // MwmHints：flags=MWM_HINTS_FUNCTIONS(2)，functions=MWM_FUNC_MOVE(1)|MWM_FUNC_RESIZE(2)=3，
    // decorations=0。属性类型即自身 atom，格式 32，长度 3。
    const uint32_t hints[3] = { 2 /*MWM_HINTS_FUNCTIONS*/, 3 /*MOVE|RESIZE*/, 0 };
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, m_window->winId(), m_motifHintsAtom,
                        m_motifHintsAtom, 32, 3, hints);
    xcb_flush(conn);
}

bool WindowGuard::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_window) {
        switch (event->type()) {
        // 窗口显示/曝光与原生窗口重建（hide/show、屏幕变更导致的 dismiss 后重建）
        // 都是 LayerShellEmulation 可能替换 flags 或丢失窗口类型属性的时机，
        // 延迟到事件处理完成后统一恢复，避免在事件派发中递归修改窗口状态。
        case QEvent::Show:
            if (auto *shell = DLayerShellWindow::get(m_window)) {
                qWarning().noquote() << "widgettoolbar: window shown, margins(top/right/bottom):"
                    << shell->topMargin() << shell->rightMargin() << shell->bottomMargin()
                    << "geometry:" << m_window->geometry();
            }
            m_geometryTicks = 0;
            m_geometryTimer.start();
            QTimer::singleShot(0, this, &WindowGuard::enforceFrameless);
            break;
        case QEvent::Expose:
            QTimer::singleShot(0, this, &WindowGuard::enforceFrameless);
            break;
        case QEvent::PlatformSurface: {
            auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
            if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
                // 原生窗口（重建）创建完成。注意该事件是 Qt postEvent 异步派发的，
                // 送达时映射请求往往已经发出，kwin 的 manage 判定已不可更改——
                // 映射前的正确属性由 Qt 自身在窗口创建时写入保证（手动类型属性
                // _q_xcb_wm_window_type + 本类/applyLayerFlags 的 flags 组合），
                // 这里的执行只是事件后的恢复与双保险。
                enforceFrameless();
            }
            break;
        }
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}
