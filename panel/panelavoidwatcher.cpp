// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "panelavoidwatcher.h"

#include "debuglogger.h"

#include <dlayershellwindow.h>
#include <dsglobal.h>

#include <QGuiApplication>
#include <QScreen>
#include <QSocketNotifier>
#include <QWindow>

#include <xcb/xcb.h>

DS_USE_NAMESPACE

Q_LOGGING_CATEGORY(panelAvoidLog, "ds.widgettoolbar.panelavoid")

namespace {

// 托盘展开小卡与悬停 tooltip 共用宿主窗（dde-shell/paneltooltip，实测
// 隐藏 13x13、tooltip 约 29x46、小卡 300x200 量级）：以映射尺寸阈值区分，
// 低于阈值按悬停提示处理、避让不触发，避免悬停一次闪一次侧栏。
constexpr int kMiniCardMinWidth = 96;
constexpr int kMiniCardMinHeight = 64;

// 托盘快捷面板宿主窗（dde-shell/panelpopup）的最小尺寸门槛：它的停驻态是
// 13x13 的占位窗，若碰巧被映射在面板区域，按"任何尺寸都算目标"会直接把面板
// 永久隐藏。占位/停驻窗一律不计。
constexpr int kPopupMinWidth = 64;
constexpr int kPopupMinHeight = 64;

// 叠合判定的容差（root 像素）：面板矩形外扩此值再与目标窗求交，使紧贴侧栏
// 边缘（差几像素）的弹出仍算冲突；严格求交会漏掉这类贴边遮挡。
constexpr int kAvoidPad = 4;

// 面板直读几何的最小可信边长（root 像素）：窗口重建/WindowGuard 纠正期间 X 侧
// 可能仍是 1x1/16x16 一类默认小窗，读值须明显大于占位才写入缓存（防污染）。
constexpr int kMinRealPanelWidth = 32;

// 对账遍历上限：深度（root=0；4 层覆盖 root→WM装饰框→Qt容器→业务窗）与窗数
// 预算。超限截断只影响"发现新目标"（事件路径不受限），避让中去留由活性直查
// 独管（reconcile R6），深度不足不再可能误撤避让。
constexpr int kMaxScanDepth = 4;
constexpr int kWalkWindowBudget = 4000;

// 从已发出的 get_property cookie 收取文本（批量预筛用：先发齐再收）
QString readTextCookie(xcb_connection_t *conn, xcb_get_property_cookie_t cookie)
{
    auto *reply = xcb_get_property_reply(conn, cookie, nullptr);
    if (!reply)
        return QString();
    QString out;
    const int len = xcb_get_property_value_length(reply);
    if (len > 0 && reply->type != XCB_ATOM_NONE) {
        const char *value = static_cast<const char *>(xcb_get_property_value(reply));
        out = QString::fromUtf8(value, len);
    }
    free(reply);
    return out;
}

// 取一个 STRING/UTF8_STRING 属性为 QString（用于 WM_NAME）
QString readTextProperty(xcb_connection_t *conn, xcb_window_t win,
                         xcb_atom_t property, xcb_atom_t type)
{
    return readTextCookie(conn,
                          xcb_get_property(conn, false, win, property, type, 0, 256));
}

// 从已发出的 WM_CLASS cookie 收取两段 NUL 分隔字符串（res_name / res_class）
void readClassCookie(xcb_connection_t *conn, xcb_get_property_cookie_t cookie,
                     QString &resName, QString &className)
{
    auto *reply = xcb_get_property_reply(conn, cookie, nullptr);
    if (!reply)
        return;
    const char *value = static_cast<const char *>(xcb_get_property_value(reply));
    const int len = xcb_get_property_value_length(reply);
    if (value && len > 0) {
        resName = QString::fromUtf8(value);
        const int second = resName.size() + 1; // 跳过首段与 NUL
        if (len > second)
            className = QString::fromUtf8(value + second, len - second);
    }
    free(reply);
}

} // namespace

PanelAvoidWatcher::PanelAvoidWatcher(QObject *parent)
    : QObject(parent)
{
    // 滞留兜底：只在 avoided 为真（面板已隐藏）期间运行——此时一次窗口树遍历
    // 成本可忽略，而漏掉一条 Unmap/Destroy 造成的"面板永久不回来"能被它纠正。
    // 见类注释「事件投递与自愈」。
    m_recheckTimer.setInterval(2000);
    m_recheckTimer.setSingleShot(false);
    connect(&m_recheckTimer, &QTimer::timeout, this, [this]() {
        if (!m_conn) {
            m_recheckTimer.stop();
            return;
        }
        qCDebug(panelAvoidLog) << "recheck tick (panel currently avoided)";
        reconcile();
    });

    // 双确认的快确认通道：首个"非权威解除"只记 1/2 并挂此单发定时器，
    // 500ms 后对在册窗口复评——真实离场此时会由第二轮确认释放，
    // 单轮瞬态误读则在此期间自纠、避让不动。
    m_releaseConfirmTimer.setInterval(500);
    m_releaseConfirmTimer.setSingleShot(true);
    connect(&m_releaseConfirmTimer, &QTimer::timeout, this, [this]() {
        if (!m_conn)
            return;
        // 走完整对账而非仅复评缓存：待确认者可能已不在树中，其陈旧缓存态
        // 恒判"仍冲突"，唯有窗口树真值能给第二轮确认（见 reconcile/reconcileWalk）。
        reconcile();
    });
}

PanelAvoidWatcher::~PanelAvoidWatcher()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        delete m_notifier;
        m_notifier = nullptr;
    }
    if (m_conn) {
        xcb_disconnect(m_conn);
        m_conn = nullptr;
    }
}

void PanelAvoidWatcher::start()
{
    if (m_conn)
        return; // 幂等

    // 仅 X11 有跨客户窗口的 SubstructureNotify 事件流
    if (QGuiApplication::platformName() != QLatin1String("xcb")) {
        qCInfo(panelAvoidLog) << "non-xcb platform, panel avoidance disabled";
        // 正常降级而非故障：Wayland 下 panelAvoided 恒 false，排查"面板被挡"时
        // 需要这条来确认避让功能本就没参与
        DebugLogger::instance()->log(
            DebugLogger::Level::Info, QStringLiteral("panelavoidwatcher"),
            QStringLiteral("avoidance disabled: platform=%1 (xcb only)").arg(
                QGuiApplication::platformName()));
        return;
    }

    int screenNum = 0;
    m_conn = xcb_connect(nullptr, &screenNum);
    if (!m_conn || xcb_connection_has_error(m_conn)) {
        qWarning() << "PanelAvoidWatcher: xcb_connect failed";
        DebugLogger::instance()->log(
            DebugLogger::Level::Error, QStringLiteral("panelavoidwatcher"),
            QStringLiteral("xcb_connect failed: avoidance permanently off this run"));
        if (m_conn) {
            xcb_disconnect(m_conn);
            m_conn = nullptr;
        }
        return;
    }

    const xcb_setup_t *setup = xcb_get_setup(m_conn);
    xcb_screen_iterator_t it = xcb_setup_roots_iterator(setup);
    for (int i = 0; i < screenNum; ++i)
        xcb_screen_next(&it);
    m_root = it.data->root;

    // 订阅 root 子树结构事件：子窗口的 Map/Unmap/Configure/Destroy 全部
    // 上报（override-redirect 与 managed 窗口皆是 root 直接子窗，覆盖两类）
    const uint32_t mask = XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY;
    xcb_change_window_attributes(m_conn, m_root, XCB_CW_EVENT_MASK, &mask);
    xcb_flush(m_conn);

    m_notifier = new QSocketNotifier(xcb_get_file_descriptor(m_conn),
                                     QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this,
            &PanelAvoidWatcher::onEvents);

    reconcile();

    qCInfo(panelAvoidLog) << "panel avoidance watcher started, root"
                          << m_root;
    // 一次插件生命周期仅一条：作为日志文件的起点锚，之后所有判定才有参照
    DebugLogger::instance()->log(
        DebugLogger::Level::Info, QStringLiteral("panelavoidwatcher"),
        QStringLiteral("watcher started: root=0x%1, initial avoided=%2")
            .arg(m_root, 0, 16)
            .arg(m_avoided));
}

// 绑定侧栏自身窗口。窗口 hide/show 重建后宿主会再次调用，故先断开上一窗口
// 的全部连接（QPointer 会自动置空，但连接必须显式解除）。Qt6 的 QWindow 无
// geometryChanged 信号，故用 x/y/width/heightChanged 四件覆盖移动与改宽（网格
// 列数、dock 边距变化、WindowGuard 几何纠正），screenChanged 覆盖换屏（DPR 变），
// visibilityChanged 覆盖首次映射——启动时面板尚未 exposed、自身矩形未知，会先
// 按"照旧避让"处理，首次曝光后经本重估自我收敛。
void PanelAvoidWatcher::attachPanel(QWindow *panel)
{
    if (m_panel.data() == panel)
        return;

    if (QWindow *old = m_panel.data())
        disconnect(old, nullptr, this, nullptr);
    m_panel = panel;
    // 刻意**不**清空 m_panelRectCached：同一侧栏的 X11 窗口 hide/show 重建后
    // 其逻辑矩形不变，缓存继续在"隐藏期"兜底；若在此清空，隐藏期直读不可用、
    // 锚定公式又暂缺（新窗口 margins 尚未回填）时 panelRect 会退化到
    // mapToGlobal 的 (0,0) 假矩形——正是避让被误撤的通道。新窗口首次可见后
    // 直读到真值即自然覆盖旧缓存。

    if (QWindow *win = m_panel.data()) {
        auto reevaluate = [this]() { reevaluateAll(); };
        connect(win, &QWindow::xChanged, this, reevaluate);
        connect(win, &QWindow::yChanged, this, reevaluate);
        connect(win, &QWindow::widthChanged, this, reevaluate);
        connect(win, &QWindow::heightChanged, this, reevaluate);
        connect(win, &QWindow::screenChanged, this, reevaluate);
        connect(win, &QWindow::visibilityChanged, this, reevaluate);
    }
    reevaluateAll();
    // attachPanel 期间没有同步读，但调用方（rootObjectChanged）刚经历过窗口创建，
    // 队列里可能已有事件被憋住 —— 顺手排水，避免依赖 fd 通知（见类注释）。
    drainEvents();
}

// 面板矩形（root 像素）。取值顺序：
//  1) 面板**可见**时：直接读它自己的 X11 窗口矩形（geometry + translate）——像素级
//     精确、含模拟层偏移、无需 DPR 折算，读到的值同时写入缓存。刻意只在可见时读：
//     面板隐藏时其原生窗口可能已被销毁，此时调用 winId() 会让 Qt 惰性重建一个位置
//     未定的窗口，读出错误矩形（那是"漏避让"的来源）。窗口重建/WindowGuard 纠正
//     期间 X 侧可能仍是默认小几何，故只接受 ≥kMinRealPanelWidth 的读值，宁缺毋滥。
//  2) 面板**隐藏**时（避让中即此情形）：用锚定公式——屏幕几何 + DLayerShellWindow
//     三边边距 + 窗口宽高（与 WindowGuard 同源），该式不依赖曝光、且跟随边距/屏幕变化。
//  3) 公式不可用则退回上次有效值。
// 已**删除 mapToGlobal 兜底**：隐藏+窗口重建期它给出贴 (0,0) 的假矩形，与右侧
// 卡片必然"不叠合"——正是避让被整轮对账误撤的通道（实测振荡与此吻合）。
// 全部失败返回空矩形表示"未知"：evaluate 对未知采取"保持现状"（不再判无冲突）。
QRect PanelAvoidWatcher::panelRect() const
{
    QWindow *panel = m_panel.data();
    if (!panel)
        return QRect();

    // 1) 可见：直读真实窗口矩形（拒绝默认小几何污染缓存）
    if (m_conn && panel->isVisible() && panel->handle()) {
        const xcb_window_t win = panel->winId();
        if (win != XCB_WINDOW_NONE) {
            auto *geo = xcb_get_geometry_reply(m_conn, xcb_get_geometry(m_conn, win), nullptr);
            auto *tr = xcb_translate_coordinates_reply(
                m_conn, xcb_translate_coordinates(m_conn, win, m_root, 0, 0), nullptr);
            const bool ok = geo && tr
                            && geo->width >= kMinRealPanelWidth
                            && geo->height >= kMinRealPanelWidth;
            const QRect rect = ok ? QRect(tr->dst_x, tr->dst_y, geo->width, geo->height) : QRect();
            if (geo)
                free(geo);
            if (tr)
                free(tr);
            if (!rect.isEmpty()) {
                m_panelRectCached = rect;
                return rect;
            }
        }
    }

    // 2) 隐藏中：优先锚定公式（不依赖曝光、跟随边距与屏幕变化）；不可用时
    //    用"上次可见时直读的精确矩形"。不再退回 mapToGlobal——它在窗口销毁/
    //    重建期给出 (0,0) 起点的假矩形，把"避让中"误翻成"无冲突"。
    QScreen *screen = panel->screen();
    const qreal dpr = screen ? screen->devicePixelRatio() : 1.0;
    if (screen && panel->width() > 0 && panel->height() > 0) {
        const int w = qRound(panel->width() * dpr);
        const int h = qRound(panel->height() * dpr);
        // 仅当确实是 layer-shell 窗口（边距非全 0）时才用锚定公式：dde-shell 的
        // DLayerShellWindow::get() 对普通窗口也可能返回一个边距全 0 的对象，照公式
        // 会算出"贴满整屏高度、y=0"的错误矩形（实测）。真实面板边距恒 ≥ contentPadding
        //（WindowGuard 也强制非 0），故该判据不会误伤真实场景。
        if (auto *shell = DLayerShellWindow::get(panel)) {
            const bool hasMargins = shell->topMargin() != 0 || shell->bottomMargin() != 0
                                    || shell->rightMargin() != 0;
            if (hasMargins) {
                const QRect sg = screen->geometry(); // DIP
                const QRect rect(qRound((sg.right() + 1) * dpr) - w - qRound(shell->rightMargin() * dpr),
                                 qRound(sg.top() * dpr) + qRound(shell->topMargin() * dpr),
                                 w, qRound((sg.height() - shell->topMargin() - shell->bottomMargin()) * dpr));
                if (!rect.isEmpty()) {
                    m_panelRectCached = rect;
                    return rect;
                }
            }
        }
    }
    // 3) 上次有效值（可能为空 = 未知）
    return m_panelRectCached;
}

// 几何叠合判定：目标窗与侧栏矩形真相交才算冲突（——托盘小卡常展开在侧栏之外的
// 托盘位，此时完全无需避让）。失败方向刻意不对称：
//  - 目标窗几何不可知 → 判为冲突（fail-closed）：它会被下一轮对账/事件重新读到，
//    不会停在未知态，保守一点无副作用；
//  - 本面板矩形不可知 → 由调用方（evaluate）单列处理，本函数只在 panel 已知时
//    被调用（未知时的"保持/释放"策略见 evaluate，不在此混为一谈）。
bool PanelAvoidWatcher::conflictsWithPanel(const WinInfo &info) const
{
    if (!info.hasPos || info.width <= 0 || info.height <= 0)
        return true;

    QRect panel = panelRect();
    if (panel.isEmpty())
        return false; // 交由 evaluate 依 panelKnown 再判定

    panel.adjust(-kAvoidPad, -kAvoidPad, kAvoidPad, kAvoidPad);
    const QRect target(info.rootX, info.rootY, info.width, info.height);
    return panel.intersects(target);
}

// 依 mapped + 目标判定 + 叠合判定翻转 counted，并刷新聚合状态。
// 进入避让（counted false→true）即时；退出避让分两类：
//  - 权威离场（authoritative=true：Unmap/Destroy、用户显式显示对账）即时释放；
//  - "身份/尺寸/叠合"这类可能被一次瞬态误读翻转的解除，走双确认，且
//    **事件驱动的评估（confirmPass=false）只记 1/2 并挂 500ms 快确认**——
//    一次逻辑变更常连发多条 X 事件，若逐条计数双确认即形同虚设（实测：
//    同一塌缩在 200ms 内连撤两轮，就是"避让几秒后自动失效"的翻版镜像）。
//    第二见只认独立复核轮（reconcile/快确认，confirmPass=true）。
// 面板矩形暂不可知：保持现状（已避让者不撤、未避让者不建），未知不等于无冲突。
void PanelAvoidWatcher::evaluate(xcb_window_t win, bool authoritative, bool confirmPass)
{
    auto it = m_windows.find(win);
    if (it == m_windows.end())
        return;
    WinInfo &info = it.value();

    // 自身窗口永不计数：身份护栏（identityTarget 的 WM_NAME 前缀）依赖窗口标题，
    // 面板窗标题一旦被改写/继承成目标样式就会自我避让——隐藏的正是自己所在的侧栏，
    // 且下一轮 reconcile 再看它一眼即自锁。这里用窗口 id 做权威判据。
    if (m_panel && m_panel->winId() == win) {
        if (info.counted) {
            info.counted = false;
            info.releasePending = 0;
            refreshAvoided();
        }
        return;
    }

    const bool targeted = info.mapped && isTarget(info);

    // 叠合判定 + 面板矩形可知性（只在目标在场时才需要）
    bool wantCounted = false;
    bool panelKnown = true;
    if (!info.mapped) {
        wantCounted = false;                    // 窗口不在：权威释放
    } else if (!targeted) {
        wantCounted = false;                    // 身份/尺寸脱靶
    } else {
        const QRect panel = panelRect();
        panelKnown = !panel.isEmpty();
        if (!panelKnown)
            // 用户显式"显示"触发的对账（authoritative）可在此释放以召回面板；
            // 被动/定时评估保持现状，不被"暂不可知"误撤。
            wantCounted = authoritative ? false : info.counted;
        else
            wantCounted = conflictsWithPanel(info); // 真叠合才算冲突
    }

    if (wantCounted) {
        if (info.releasePending != 0)
            info.releasePending = 0;            // 恢复冲突：撤销待释放计数
        if (!info.counted) {
            info.counted = true;
            if (targeted)
                qWarning().noquote() << "panelavoid: AVOID ON, culprit" << info.name
                                     << info.className << "/" << info.resName
                                     << "rect=" << QRect(info.rootX, info.rootY, info.width, info.height)
                                     << "panel=" << panelRect();
            refreshAvoided();
        }
        return;
    }

    // wantCounted == false —— 需要释放
    if (!info.counted)
        return;                                 // 本就没避让，无需处理

    // 面板矩形不可知的"保持"分支不会走到这里（wantCounted==info.counted）。
    // 走到此处的解除：Unmap/消失或 authoritative 事件即时释放；否则双确认。
    const bool immediate = authoritative || !info.mapped;
    if (immediate) {
        info.counted = false;
        info.releasePending = 0;
        if (targeted || info.mapped)
            qCDebug(panelAvoidLog) << "keep panel (released)" << win << info.name;
        refreshAvoided();
        return;
    }

    // 非权威解除。事件驱动：只把 pending 从 0 抬到 1 并挂快确认，绝不从 1
    // 抬到 2（那一步只属于复核轮），使同一次变更连发的多条事件只算一次发现。
    if (!confirmPass) {
        if (info.releasePending == 0) {
            info.releasePending = 1;
            qWarning().noquote() << "panelavoid: release candidate (1/2)" << win
                                 << info.name << "panel=" << panelRect()
                                 << "confirming shortly";
            armReleaseConfirm();
        }
        return;
    }

    // 复核轮（reconcile / 500ms 快确认）：这是独立第二轮观测。
    if (info.releasePending < 1) {
        info.releasePending = 1;                 // 本轮仅首轮发现，待再一轮回看
        armReleaseConfirm();
    } else {
        info.counted = false;                    // 第二轮仍无冲突 → 确认释放
        info.releasePending = 0;
        qWarning().noquote() << "panelavoid: keep panel (confirmed no conflict)"
                             << win << info.name;
        refreshAvoided();
    }
}

// 立即按真值重建状态。面板在"用户要求显示"时调用它：先对账再决定是否隐藏，
// 于是按显示按钮永远能把面板叫回来（除非确实存在冲突窗口）。
void PanelAvoidWatcher::recheck()
{
    if (!m_conn)
        return;
    reconcile(true);
}

// 面板矩形变化后重估全部在册窗口：evaluate 只在 counted 翻转时才刷新聚合态，
// 逐窗调用无副作用。
void PanelAvoidWatcher::reevaluateAll()
{
    if (m_windows.isEmpty())
        return;
    const auto windows = m_windows; // 快照，避免 evaluate 内改动容器
    for (auto it = windows.constBegin(); it != windows.constEnd(); ++it) {
        if (it->mapped)
            evaluate(it.key());
    }
}

void PanelAvoidWatcher::onEvents()
{
    drainEvents();
    // 丢弃错误事件（含 BadWindow：对账竞态中窗口可能已销毁）
    if (xcb_connection_has_error(m_conn)) {
        qWarning() << "PanelAvoidWatcher: connection error, watcher stopping";
        m_notifier->setEnabled(false);
    }
}

// 把 xcb 内部队列里的事件全部取出处理。
// 为什么不能只靠 QSocketNotifier：同步往返（xcb_get_property/_geometry/
// translate_coordinates 的 *_reply）会一直读到找到应答为止，期间到达的事件被
// 读进 xcb 内部队列、socket 被读空 —— 此后 fd 不再可读，通知器不会触发，队列里
// 的事件就一直"憋着"。实测（同一连接、先让 MapNotify 到达、再做一次同步往返）：
//   fd 可读 = 0；而 xcb_poll_for_event 仍能取出该 MapNotify。
// 因此每批同步读之后都要显式排水，否则漏掉的一条 Unmap/Destroy 会让某个窗口永远
// 停留在 counted=true、avoided 永久为真、面板永久不显示。
void PanelAvoidWatcher::drainEvents()
{
    if (!m_conn)
        return;
    while (xcb_generic_event_t *ev = xcb_poll_for_event(m_conn)) {
        handleEvent(ev);
        free(ev);
    }
}

void PanelAvoidWatcher::handleEvent(xcb_generic_event_t *event)
{
    const uint8_t type = event->response_type & ~static_cast<uint8_t>(0x80);
    switch (type) {
    case XCB_MAP_NOTIFY: {
        auto *e = reinterpret_cast<xcb_map_notify_event_t *>(event);
        // 对该窗直接订阅，覆盖随后被 WM reparent 的情形
        selectEvents(e->window);
        WinInfo &info = m_windows[e->window];
        info.mapped = true;
        fetchIdentity(e->window, info);
        evaluate(e->window);
        // fetchIdentity 的同步往返已掏空 fd 并把期间事件憋进内部队列；此刻
        // 调用方的 WinInfo& 已离开作用域，安全排水（见类注释「事件投递与自愈」）
        drainEvents();
        break;
    }
    case XCB_UNMAP_NOTIFY: {
        auto *e = reinterpret_cast<xcb_unmap_notify_event_t *>(event);
        auto it = m_windows.find(e->window);
        if (it == m_windows.end())
            break;
        it->mapped = false;
        // 权威离场：目标真的不在了，避让即刻解除（关卡通窗口的 UX 首要是快）
        evaluate(e->window, true);
        break;
    }
    case XCB_CONFIGURE_NOTIFY: {
        auto *e = reinterpret_cast<xcb_configure_notify_event_t *>(event);
        auto it = m_windows.find(e->window);
        if (it == m_windows.end() || !it->mapped)
            break;
        it->width = e->width;
        it->height = e->height;
        // 几何变化可能只动位置不动尺寸（小卡换托盘图标位置、WM 摆放推迟到
        // 映射之后），故同步重读绝对位置：e->x/y 为父窗相对，被 reparent 的
        // 客户端必须 translate 才是 root 坐标
        fetchRootPosition(e->window, it.value());
        // tooltip 窗在小卡/悬停提示间复用可能仅改尺寸不重映射，重估阈值
        evaluate(e->window);
        break;
    }
    case XCB_DESTROY_NOTIFY: {
        auto *e = reinterpret_cast<xcb_destroy_notify_event_t *>(event);
        auto it = m_windows.find(e->window);
        if (it == m_windows.end())
            break;
        const bool wasCounted = it->counted;
        m_windows.erase(it);
        if (wasCounted)
            refreshAvoided();
        break;
    }
    case XCB_CREATE_NOTIFY: {
        auto *e = reinterpret_cast<xcb_create_notify_event_t *>(event);
        // 仅登记 root 直接创建的顶层窗（映射前建档，订阅其自身事件）
        if (e->parent != m_root)
            break;
        if (!m_windows.contains(e->window)) {
            WinInfo info;
            info.mapped = false;
            m_windows.insert(e->window, info);
        }
        selectEvents(e->window);
        break;
    }
    case XCB_REPARENT_NOTIFY: {
        // 客户端被 WM 收进装饰框：其 Map/Unmap 之后上报给新父而非 root。
        // 对客户端与其新父都直接订阅，并回读当前映射态，覆盖 reparent
        // 早于本次订阅到达的竞态（新父=0 表示移出屏幕，交 Unmap 逻辑）。
        auto *e = reinterpret_cast<xcb_reparent_notify_event_t *>(event);
        auto *attr = xcb_get_window_attributes_reply(
            m_conn, xcb_get_window_attributes(m_conn, e->window), nullptr);
        if (!attr)
            break;
        const bool viewable = attr->map_state == XCB_MAP_STATE_VIEWABLE;
        free(attr);
        selectEvents(e->window);
        if (e->parent)
            selectEvents(e->parent);
        WinInfo &info = m_windows[e->window];
        if (viewable) {
            info.mapped = true;
            fetchIdentity(e->window, info);
        }
        evaluate(e->window);
        break;
    }
    case XCB_PROPERTY_NOTIFY: {
        // WM_NAME / WM_CLASS 常在 map 之后才写入：属性到达时补身份并重估
        auto *e = reinterpret_cast<xcb_property_notify_event_t *>(event);
        if (e->atom != XCB_ATOM_WM_NAME && e->atom != XCB_ATOM_WM_CLASS)
            break;
        auto it = m_windows.find(e->window);
        if (it == m_windows.end() || !it->mapped)
            break;
        fetchIdentity(e->window, it.value());
        evaluate(e->window);
        break;
    }
    default:
        break;
    }
}

// 对该窗订阅：SubstructureNotify 收其子窗（客户端）的 Map/Unmap/Configure，
// StructureNotify 收其自身结构变化，PropertyChange 收 WM_NAME/WM_CLASS 延迟
// 写入。用于三类窗口：被 reparent 的客户端、其新父装饰框、对账递归经过的窗，
// 使 root 之下任意层级窗口的映射都能被跟踪（含 WM 装饰框内的托管应用窗）
void PanelAvoidWatcher::selectEvents(xcb_window_t win)
{
    const uint32_t mask = XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY
                          | XCB_EVENT_MASK_STRUCTURE_NOTIFY
                          | XCB_EVENT_MASK_PROPERTY_CHANGE;
    xcb_change_window_attributes(m_conn, win, XCB_CW_EVENT_MASK, &mask);
}

void PanelAvoidWatcher::fetchIdentity(xcb_window_t win, WinInfo &info)
{
    // 粘滞身份：合法目标窗的 WM_NAME 不会自己变成空，空只可能是瞬态读失败
    // （属性恰在被替换/窗口恰在重建）。一次空读不得让已建档的目标脱靶——
    // 读到空值时保留上一次成功的非空值；新字段成功读到才覆盖。
    const QString name = readTextProperty(m_conn, win, XCB_ATOM_WM_NAME,
                                          XCB_ATOM_ANY); // 任意类型（UTF8/STRING）
    if (!name.isEmpty())
        info.name = name;

    // WM_CLASS 为两段 NUL 分隔字符串：res_name / res_class（同上，空读不覆盖）
    QString resName;
    QString className;
    readClassCookie(m_conn,
                    xcb_get_property(m_conn, false, win, XCB_ATOM_WM_CLASS,
                                     XCB_ATOM_STRING, 0, 256),
                    resName, className);
    if (!resName.isEmpty())
        info.resName = resName;
    if (!className.isEmpty())
        info.className = className;

    auto *geo = xcb_get_geometry_reply(m_conn, xcb_get_geometry(m_conn, win),
                                       nullptr);
    if (geo) {
        info.width = geo->width;
        info.height = geo->height;
        free(geo);
    }

    fetchRootPosition(win, info);

    qCDebug(panelAvoidLog) << "mapped" << win << "name=" << info.name
                           << "class=" << info.className << "/" << info.resName
                           << "size=" << info.width << "x" << info.height
                           << "pos=" << info.rootX << "+" << info.rootY
                           << "target=" << isTarget(info);

    // 本函数刻意不在此排水：调用方多持有 WinInfo& / 迭代器，drainEvents 可能经
    // DestroyNotify 改容器而致悬垂（悬垂引用即状态误翻的隐因）。排水统一放在
    // 各同步读批次**结束后**（见 handleEvent 的 Map 分支末尾、reconcile 末尾）。
}

// 该窗左上角在 root 坐标系中的绝对位置（像素）。override-redirect 窗的父即
// root，managed 窗被 WM reparent 进装饰框后父为框架窗——translate 对两者都
// 给出正确的绝对位置（不含装饰框偏移，正是我们要的客户区）。失败（窗口已
// 销毁的竞态）清 hasPos，由 conflictsWithPanel 退化为"照旧避让"。
void PanelAvoidWatcher::fetchRootPosition(xcb_window_t win, WinInfo &info)
{
    auto *tr = xcb_translate_coordinates_reply(
        m_conn, xcb_translate_coordinates(m_conn, win, m_root, 0, 0), nullptr);
    if (!tr) {
        info.hasPos = false;
        return;
    }
    info.rootX = tr->dst_x;
    info.rootY = tr->dst_y;
    info.hasPos = true;
    free(tr);
}

// 身份命中（不看尺寸阈值）：对账预筛判据。展开/收起动画中间帧或尚未读到几何时，
// 尺寸门槛不可判，但身份前缀/类名已足以决定是否补一次全量 fetchIdentity。
bool PanelAvoidWatcher::identityTarget(const WinInfo &info) const
{
    const QString &name = info.name;

    // 本面板自身窗口与弹窗永不匹配（防自触发）
    if (name.startsWith(QLatin1String("org.deepin.ds.widgettoolbar"))
        || name.startsWith(QLatin1String("dde-shell/widgettoolbar")))
        return false;

    if (name == QLatin1String("org.deepin.ds.notificationbubble")
        || name == QLatin1String("org.deepin.ds.notificationcenter")
        || name == QLatin1String("org.deepin.ds.dde-shutdown"))
        return true;
    if (name.startsWith(QLatin1String("dde-shell/panelpopup"))
        || name.startsWith(QLatin1String("dde-shell/paneltooltip")))
        return true;

    if (info.className.compare(QLatin1String("dde-control-center"),
                               Qt::CaseInsensitive) == 0
        || info.resName.compare(QLatin1String("dde-control-center"),
                                Qt::CaseInsensitive) == 0)
        return true;
    if (info.className.compare(QLatin1String("dde-clipboard"),
                               Qt::CaseInsensitive) == 0
        || info.resName.compare(QLatin1String("dde-clipboard"),
                                Qt::CaseInsensitive) == 0)
        return true;
    return false;
}

bool PanelAvoidWatcher::isTarget(const WinInfo &info) const
{
    const QString &name = info.name;

    // 托盘快捷面板宿主窗：尺寸达阈值才避让。该窗同时承载停驻占位（实测 13x13），
    // 若占位窗被映射在面板区域，"任何尺寸都算"会直接把面板永久隐藏。
    if (name.startsWith(QLatin1String("dde-shell/panelpopup")))
        return info.width >= kPopupMinWidth && info.height >= kPopupMinHeight;
    // 托盘展开小卡：与悬停 tooltip 同窗，尺寸达阈值才算小卡
    if (name.startsWith(QLatin1String("dde-shell/paneltooltip")))
        return info.width >= kMiniCardMinWidth && info.height >= kMiniCardMinHeight;

    // 其余（精确标题窗、独立应用类名）无尺寸门槛，身份命中即目标
    return identityTarget(info);
}

void PanelAvoidWatcher::refreshAvoided()
{
    const WinInfo *culprit = nullptr;
    for (const WinInfo &info : std::as_const(m_windows)) {
        if (info.counted) {
            culprit = &info;
            break;
        }
    }
    // 释放也用 qWarning：dde-shell 以 QT_LOGGING_RULES=*.info=false 运行，
    // info 级决策日志线上不可见（避让振荡排查正是被这个盲区拖慢的）。
    if (!culprit && m_avoided)
        qWarning().noquote() << "panelavoid: OFF (no conflicting window)";
    // 只在跃变时落文件日志：本函数由每条结构事件与 2 s 兜底对账驱动，避让常驻
    // 时属高频点，无条件记录会以每 2 s 数行的速度刷满配额。此刻 m_avoided 仍是
    // 变更前旧值，故与 next 不等即为真实跃变；panelRect() 有 X 往返，也只在此
    // 低频分支里调用。
    const bool nextAvoided = culprit != nullptr;
    if (nextAvoided != m_avoided) {
        int counted = 0;
        for (const WinInfo &info : std::as_const(m_windows)) {
            if (info.counted)
                ++counted;
        }
        const QRect rect = panelRect();
        const QString rectText = rect.isValid()
            ? QStringLiteral("%1,%2 %3x%4")
                  .arg(rect.x()).arg(rect.y()).arg(rect.width()).arg(rect.height())
            : QStringLiteral("(unknown)");
        DebugLogger::instance()->log(
            DebugLogger::Level::Info, QStringLiteral("panelavoidwatcher"),
            nextAvoided
                ? QStringLiteral("AVOID ON: culprit=%1 counted=%2/%3 panel=%4")
                      .arg(culprit->name.isEmpty() ? QStringLiteral("(unnamed)") : culprit->name)
                      .arg(counted)
                      .arg(m_windows.size())
                      .arg(rectText)
                : QStringLiteral("AVOID OFF: counted=0/%1 panel=%2")
                      .arg(m_windows.size())
                      .arg(rectText));
    }
    setAvoided(culprit != nullptr);
}

void PanelAvoidWatcher::setAvoided(bool avoided)
{
    if (m_avoided == avoided)
        return;
    m_avoided = avoided;
    // 仅在避让期间跑兜底对账：面板已隐藏，遍历成本可忽略，而它能纠正任何
    // 漏事件造成的滞留（见类注释「事件投递与自愈」）。
    if (m_avoided)
        m_recheckTimer.start();
    else
        m_recheckTimer.stop();
    if (!avoided)
        m_releaseConfirmTimer.stop();
    Q_EMIT avoidedChanged(avoided);
}

void PanelAvoidWatcher::armReleaseConfirm()
{
    if (!m_releaseConfirmTimer.isActive())
        m_releaseConfirmTimer.start();
}

// 按窗口树真值重建状态。**"扫不到"绝不等于"已消失"**：
//  1) 逐层批量遍历（reconcileWalk）重建"见到"集合；
//  2) 避让中但未见者走活性直查（R6）：自身 map_state 仍 VIEWABLE → 记为见到、
//     避让保持；已销毁/失活（读不到属性、UNMAPPED，或祖先被收起导致的
//     UNVIEWABLE）→ 权威释放。dde 展开卡片实测是 root 直接子窗、以销毁→重建
//     换 id 的方式轮换，叠加 X11 下 kwin 反复 reparent——任一情形都能让某轮扫描
//     一时漏见它；旧实现"未见两轮即删"把"扫不到"误当"已离场"，正是"避让几秒后
//     自动失效"振荡的通道，活性直查把释放判据与扫描可见性解耦；
//  3) 未避让且未见者为纯垃圾条目，直接删除（需要时由事件路径重建）；
//  4) 见到者统一走复核轮评估（confirmPass=true），与事件驱动的 1/2 标记
//     共同构成"两次独立观测"。
// userRequested=true（托盘/任务栏按钮要求显示）时评估按权威路径执行：面板矩形
// 暂不可知的避让条目也会即刻释放，保证按钮总能召回面板。
void PanelAvoidWatcher::reconcile(bool userRequested)
{
    if (!m_conn)
        return;

    m_seen.clear();
    reconcileWalk();

    // R6 活性直查：避让中但扫描未见者，以自身窗口 id 的属性裁决去留
    for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
        if (!it->counted || m_seen.contains(it.key()))
            continue;
        auto *attr = xcb_get_window_attributes_reply(
            m_conn, xcb_get_window_attributes(m_conn, it.key()), nullptr);
        if (!attr && xcb_connection_has_error(m_conn)) {
            qWarning().noquote() << "panelavoid: connection error during liveness probe"
                                 << "— reconcile aborts, avoidance unchanged";
            DebugLogger::instance()->log(
                DebugLogger::Level::Error, QStringLiteral("panelavoidwatcher"),
                QStringLiteral("connection error during liveness probe: reconcile aborted, "
                               "avoidance left unchanged"));
            return; // 连接坏了不能拿"读不到"当"窗口没了"
        }
        const bool viewable = attr && attr->map_state == XCB_MAP_STATE_VIEWABLE;
        if (attr)
            free(attr);
        if (viewable) {
            m_seen.insert(it.key()); // 仍可见：当作见到，走统一复核（几何由事件流保鲜）
            continue;
        }
        qWarning().noquote() << "panelavoid: released on liveness probe" << it->name
                             << "win=" << it.key()
                             << "(window gone or no longer viewable)"
                             << "panel=" << panelRect();
        // 权威释放：这是避让真正解除的三条通道之一，且只在窗口确实销毁/不可见
        // 时发生（非每轮对账），低频且信息量高，值得单独留一条
        DebugLogger::instance()->log(
            DebugLogger::Level::Info, QStringLiteral("panelavoidwatcher"),
            QStringLiteral("released on liveness probe: %1 win=0x%2 (gone or not viewable)")
                .arg(it->name.isEmpty() ? QStringLiteral("(unnamed)") : it->name)
                .arg(it.key(), 0, 16));
        it->counted = false;
        it->mapped = false;
        it->releasePending = 0;
    }

    // 未见且未避让：垃圾，删
    int pruned = 0;
    for (auto it = m_windows.begin(); it != m_windows.end();) {
        if (m_seen.contains(it.key())) {
            ++it;
            continue;
        }
        it = m_windows.erase(it);
        ++pruned;
    }
    if (pruned > 0)
        qCDebug(panelAvoidLog) << "reconcile pruned" << pruned << "entries,"
                               << m_windows.size() << "remain";

    // 统一复核评估：只评本轮见到的条目（confirmPass=true）
    const auto windows = m_windows;
    for (auto it = windows.constBegin(); it != windows.constEnd(); ++it) {
        if (m_seen.contains(it.key()))
            evaluate(it.key(), userRequested, true);
    }
    refreshAvoided();

    // 对账期间全是同步往返，队列里可能已憋住事件：立刻排水（见 drainEvents 注释）
    drainEvents();
}

// 逐层批量遍历 root 窗口树（见类注释"对账成本控制"）：query_tree、attributes、
// WM_NAME/WM_CLASS 预筛均按层"先发齐请求再收回复"，同步等待只发生在层边界；
// 全量 fetchIdentity（几何/位置）仅补发给身份命中或本就建档的窗。
// 见到的窗一律 m_seen + selectEvents（深层窗的后续事件经直接订阅直达）。
void PanelAvoidWatcher::reconcileWalk()
{
    QVector<xcb_window_t> level;
    level.append(m_root);
    QHash<xcb_window_t, xcb_window_t> visitedMap; // win→parent，兼作去重
    visitedMap.insert(m_root, 0);
    int visited = 0;
    bool truncated = false;

    for (int depth = 1; depth <= kMaxScanDepth && !level.isEmpty() && !truncated; ++depth) {
        // 1) 批量 query_tree(当前层) → 下一层候选
        QVector<xcb_window_t> next;
        QVector<xcb_query_tree_cookie_t> treeCookies;
        treeCookies.reserve(level.size());
        for (const xcb_window_t w : std::as_const(level))
            treeCookies.append(xcb_query_tree(m_conn, w));
        for (int i = 0; i < level.size(); ++i) {
            auto *tree = xcb_query_tree_reply(m_conn, treeCookies.at(i), nullptr);
            if (!tree)
                continue;
            const int n = xcb_query_tree_children_length(tree);
            const xcb_window_t *ch = xcb_query_tree_children(tree);
            for (int j = 0; j < n; ++j) {
                if (visitedMap.contains(ch[j]))
                    continue;
                if (++visited > kWalkWindowBudget) {
                    qWarning().noquote() << "panelavoid: walk budget exceeded at depth"
                                         << depth << "— scan truncated this round";
                    truncated = true;
                    break;
                }
                visitedMap.insert(ch[j], level.at(i));
                next.append(ch[j]);
            }
            free(tree);
            if (truncated)
                break;
        }

        // 2) 批量 attributes → 只留已映射者（未映射分支不再下探，也自然不入 seen；
        //    其中避让中者由 R6 活性直查单独裁决，不受扫描深度影响）
        QVector<xcb_get_window_attributes_cookie_t> attrCookies;
        attrCookies.reserve(next.size());
        for (const xcb_window_t w : std::as_const(next))
            attrCookies.append(xcb_get_window_attributes(m_conn, w));
        level.clear();
        for (int i = 0; i < next.size(); ++i) {
            auto *attr = xcb_get_window_attributes_reply(m_conn, attrCookies.at(i), nullptr);
            const bool viewable = attr && attr->map_state == XCB_MAP_STATE_VIEWABLE;
            if (attr)
                free(attr);
            if (viewable)
                level.append(next.at(i));
        }

        // 3) 批量身份预筛（每窗 WM_NAME + WM_CLASS 两 cookie，一并收取）
        QVector<xcb_get_property_cookie_t> idCookies;
        idCookies.reserve(level.size() * 2);
        for (const xcb_window_t w : std::as_const(level)) {
            idCookies.append(xcb_get_property(m_conn, false, w, XCB_ATOM_WM_NAME,
                                              XCB_ATOM_ANY, 0, 256));
            idCookies.append(xcb_get_property(m_conn, false, w, XCB_ATOM_WM_CLASS,
                                              XCB_ATOM_STRING, 0, 256));
        }
        QVector<xcb_window_t> fullFetch;
        for (int i = 0; i < level.size(); ++i) {
            const xcb_window_t w = level.at(i);
            m_seen.insert(w);
            selectEvents(w);

            WinInfo probe;
            probe.mapped = true;
            probe.name = readTextCookie(m_conn, idCookies.at(2 * i));
            readClassCookie(m_conn, idCookies.at(2 * i + 1),
                            probe.resName, probe.className);

            const bool registered = m_windows.contains(w);
            if (registered) {
                // 粘滞合并：空读不覆盖在册非空值；判定用合并后的身份
                WinInfo &old = m_windows[w];
                old.mapped = true;
                if (!probe.name.isEmpty())
                    old.name = probe.name;
                if (!probe.resName.isEmpty())
                    old.resName = probe.resName;
                if (!probe.className.isEmpty())
                    old.className = probe.className;
                probe = old;
            }
            if (identityTarget(probe)) {
                if (!registered)
                    m_windows.insert(w, probe);
                fullFetch.append(w); // 补全量几何/位置
            } else if (registered) {
                fullFetch.append(w); // 在册非目标（如 13x13 驻停 popup）：刷几何以判阈值回升
            }
            // 身份不命中且未建档：不建档；其映射会由 Map 事件另行建档
        }

        // 4) 候选者补全量身份+几何（数量受目标窗自然约束）
        for (const xcb_window_t w : std::as_const(fullFetch))
            fetchIdentity(w, m_windows[w]);
    }
}
