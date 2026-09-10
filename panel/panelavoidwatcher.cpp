// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "panelavoidwatcher.h"

#include <QGuiApplication>
#include <QScreen>
#include <QSocketNotifier>
#include <QWindow>

#include <xcb/xcb.h>

Q_LOGGING_CATEGORY(panelAvoidLog, "ds.widgettoolbar.panelavoid")

namespace {

// 托盘展开小卡与悬停 tooltip 共用宿主窗（dde-shell/paneltooltip，实测
// 隐藏 13x13、tooltip 约 29x46、小卡 300x200 量级）：以映射尺寸阈值区分，
// 低于阈值按悬停提示处理、避让不触发，避免悬停一次闪一次侧栏。
constexpr int kMiniCardMinWidth = 96;
constexpr int kMiniCardMinHeight = 64;

// 叠合判定的容差（root 像素）：面板矩形外扩此值再与目标窗求交，使紧贴侧栏
// 边缘（差几像素）的弹出仍算冲突；严格求交会漏掉这类贴边遮挡。
constexpr int kAvoidPad = 4;

// 取一个 STRING/UTF8_STRING 属性为 QString（用于 WM_NAME）
QString readTextProperty(xcb_connection_t *conn, xcb_window_t win,
                         xcb_atom_t property, xcb_atom_t type)
{
    auto *reply = xcb_get_property_reply(
        conn,
        xcb_get_property(conn, false, win, property, type, 0, 256),
        nullptr);
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

} // namespace

PanelAvoidWatcher::PanelAvoidWatcher(QObject *parent)
    : QObject(parent)
{
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
        return;
    }

    int screenNum = 0;
    m_conn = xcb_connect(nullptr, &screenNum);
    if (!m_conn || xcb_connection_has_error(m_conn)) {
        qWarning() << "PanelAvoidWatcher: xcb_connect failed";
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

    reconcileInitial();

    qCInfo(panelAvoidLog) << "panel avoidance watcher started, root"
                          << m_root;
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
    m_panelRectCached = QRect();

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
}

// 面板矩形（root 像素）：QWindow 几何为 DIP，需按本屏 DPR 折算才能与 xcb 读到的
// 目标窗像素矩形同域比较。未 exposed（尚未首次映射，或正处避让隐藏中）时几何
// 不可信，退回上一次有效值；两者皆无返回空矩形表示"未知"。
QRect PanelAvoidWatcher::panelRect() const
{
    if (!m_panel.data())
        return QRect();

    if (m_panel->isExposed()) {
        if (QScreen *screen = m_panel->screen()) {
            const qreal dpr = screen->devicePixelRatio();
            const QPoint global = m_panel->mapToGlobal(QPoint(0, 0)); // DIP
            const QRect rect(qRound(global.x() * dpr), qRound(global.y() * dpr),
                             qRound(m_panel->width() * dpr),
                             qRound(m_panel->height() * dpr));
            if (!rect.isEmpty()) {
                m_panelRectCached = rect; // 供随后隐藏期间使用
                return rect;
            }
        }
    }
    return m_panelRectCached;
}

// 几何叠合判定：目标窗与侧栏矩形真相交才算冲突（回归点——托盘小卡常展开在
// 侧栏之外的托盘位，此时完全无需避让）。所有"读不到"的分支一律返回 true，
// 保持旧的弹出即避让行为，不因判定材料缺失而漏避。
bool PanelAvoidWatcher::conflictsWithPanel(const WinInfo &info) const
{
    if (!info.hasPos || info.width <= 0 || info.height <= 0)
        return true;

    QRect panel = panelRect();
    if (panel.isEmpty())
        return true;

    panel.adjust(-kAvoidPad, -kAvoidPad, kAvoidPad, kAvoidPad);
    const QRect target(info.rootX, info.rootY, info.width, info.height);
    return panel.intersects(target);
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
    while (xcb_generic_event_t *ev = xcb_poll_for_event(m_conn)) {
        handleEvent(ev);
        free(ev);
    }
    // 丢弃错误事件（含 BadWindow：对账竞态中窗口可能已销毁）
    if (xcb_connection_has_error(m_conn)) {
        qWarning() << "PanelAvoidWatcher: connection error, watcher stopping";
        m_notifier->setEnabled(false);
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
        break;
    }
    case XCB_UNMAP_NOTIFY: {
        auto *e = reinterpret_cast<xcb_unmap_notify_event_t *>(event);
        auto it = m_windows.find(e->window);
        if (it == m_windows.end())
            break;
        it->mapped = false;
        evaluate(e->window);
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
    info.name = readTextProperty(m_conn, win, XCB_ATOM_WM_NAME,
                                 XCB_ATOM_ANY); // 任意类型（UTF8/STRING）

    // WM_CLASS 为两段 NUL 分隔字符串：res_name / res_class
    auto *reply = xcb_get_property_reply(
        m_conn,
        xcb_get_property(m_conn, false, win, XCB_ATOM_WM_CLASS,
                         XCB_ATOM_STRING, 0, 256),
        nullptr);
    info.resName.clear();
    info.className.clear();
    if (reply) {
        const char *value = static_cast<const char *>(xcb_get_property_value(reply));
        const int len = xcb_get_property_value_length(reply);
        if (value && len > 0) {
            info.resName = QString::fromUtf8(value);
            const int second = info.resName.size() + 1; // 跳过首段与 NUL
            if (len > second)
                info.className = QString::fromUtf8(value + second, len - second);
        }
        free(reply);
    }

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

bool PanelAvoidWatcher::isTarget(const WinInfo &info) const
{
    const QString &name = info.name;

    // 本面板自身窗口与弹窗永不匹配（防自触发）
    if (name.startsWith(QLatin1String("org.deepin.ds.widgettoolbar"))
        || name.startsWith(QLatin1String("dde-shell/widgettoolbar")))
        return false;

    // DS 面板包窗口：WM_NAME 即 pluginId（实测 notificationbubble 等）
    if (name == QLatin1String("org.deepin.ds.notificationbubble")
        || name == QLatin1String("org.deepin.ds.notificationcenter")
        || name == QLatin1String("org.deepin.ds.dde-shutdown"))
        return true;

    // 托盘快捷面板宿主窗：任何映射都避让
    if (name.startsWith(QLatin1String("dde-shell/panelpopup")))
        return true;

    // 托盘展开小卡：与悬停 tooltip 同窗，尺寸达阈值才算小卡
    if (name.startsWith(QLatin1String("dde-shell/paneltooltip"))
        && info.width >= kMiniCardMinWidth && info.height >= kMiniCardMinHeight)
        return true;

    // 独立应用：按 WM_CLASS（res_class 主，res_name 兜底；Qt 落点大小写
    // 不一，比对忽略大小写）
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

void PanelAvoidWatcher::evaluate(xcb_window_t win)
{
    auto it = m_windows.find(win);
    if (it == m_windows.end())
        return;
    WinInfo &info = it.value();
    // 三段与：映射 → 身份/尺寸命中 → 与侧栏几何叠合。前两段是"是不是它"，
    // 最后一段是"是否真挡住"；身份命中但位置不冲突者不再触发避让（回归修复）。
    const bool counted = info.mapped && isTarget(info) && conflictsWithPanel(info);
    if (counted == info.counted)
        return;
    info.counted = counted;
    if (info.mapped && isTarget(info)) {
        qCDebug(panelAvoidLog) << (counted ? "avoid" : "keep panel")
                               << win << info.name << "rect=" << info.rootX
                               << info.rootY << info.width << "x" << info.height
                               << "panel=" << panelRect();
    }
    refreshAvoided();
}

void PanelAvoidWatcher::refreshAvoided()
{
    bool any = false;
    for (const WinInfo &info : std::as_const(m_windows)) {
        if (info.counted) {
            any = true;
            break;
        }
    }
    setAvoided(any);
}

void PanelAvoidWatcher::setAvoided(bool avoided)
{
    if (m_avoided == avoided)
        return;
    m_avoided = avoided;
    Q_EMIT avoidedChanged(avoided);
}

void PanelAvoidWatcher::reconcileInitial()
{
    reconcileWindow(m_root, 0);
    // 对账后立即收敛聚合状态（可能启动即处于避让场景）
    refreshAvoided();
}

// 递归遍历窗口子树（深度上限 2，覆盖 root→WM装饰框→客户端 与 root→覆盖窗
// 两类），对每个可见窗建档评估，并对顶层窗订阅自身事件
void PanelAvoidWatcher::reconcileWindow(xcb_window_t win, int depth)
{
    auto *attr = xcb_get_window_attributes_reply(
        m_conn, xcb_get_window_attributes(m_conn, win), nullptr);
    const bool viewable = attr && attr->map_state == XCB_MAP_STATE_VIEWABLE;
    if (attr)
        free(attr);
    if (!viewable && depth > 0)
        return; // 未映射分支不进入其子树，省查询

    if (depth > 0) {
        WinInfo &info = m_windows[win];
        info.mapped = viewable;
        if (viewable) {
            fetchIdentity(win, info);
            selectEvents(win);
            evaluate(win);
        }
    }

    if (depth >= 2)
        return;
    auto *tree = xcb_query_tree_reply(m_conn, xcb_query_tree(m_conn, win),
                                      nullptr);
    if (!tree)
        return;
    const int n = xcb_query_tree_children_length(tree);
    const xcb_window_t *children = xcb_query_tree_children(tree);
    for (int i = 0; i < n; ++i)
        reconcileWindow(children[i], depth + 1);
    free(tree);
}
