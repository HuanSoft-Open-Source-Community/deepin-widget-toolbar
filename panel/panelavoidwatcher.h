// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QLoggingCategory>
#include <QObject>
#include <QHash>
#include <QPointer>
#include <QRect>
#include <QSet>
#include <QTimer>

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
// 面板位置不冲突，无需避让。
// 失败方向刻意不对称：**本面板矩形不可知时判为"不冲突"（fail-open），但仅对
// 尚未避让的条目成立**——误避会让面板永久消失；而已避让者遇面板矩形暂不可知
// 时**保持现状**（隐藏期读不到自身窗口是常态，未知不构成"无冲突"的证据）。
// 目标窗几何不可知时按"冲突"处理（fail-closed），它会被下一轮对账/事件重新读到。
// DPI 折算用本面板所在屏的 devicePixelRatio（QWindow 几何为 DIP，X11 为像素）：
// 单屏或各屏同缩放时精确，混合 DPR 多屏存在原点误差（此时最坏退化为误判叠合，
// 由目标窗 ConfigureNotify 与本面板位置/尺寸变化事件重估自我收敛）。
//
// 事件投递与自愈（重要）：本类用自己的 xcb 连接，只在 QSocketNotifier(fd 可读)
// 触发时排水；而同步往返（fetchIdentity/reconcile 里的 *_reply）会把期间到达的
// 事件读进 xcb 内部队列并掏空 fd —— 此时通知器不会触发，事件会被"憋住"。因此：
//   1) 同步读批次结束后统一 drainEvents()（fetchIdentity 内部不排水，以免在
//      调用方持有 WinInfo& 时经事件处理改容器——悬垂引用即误翻状态之源）；
//   2) recheck() 按窗口树真值重建状态；**"扫不到"与"窗口消失"绝不划等号**：
//      避让中的条目无论是否被扫描见到，都按自身窗口 id 直接活性核查（get_window_
//      attributes）——已销毁（无属性可答）或不可见（UNMAPPED/UNVIEWABLE，宿主被
//      收起时子窗即报 UNVIEWABLE）才权威释放；仍 VIEWABLE 即视为见到、避让保持。
//      实测（探针 2026-09-11）：dde 展开卡片是 root 直接子窗，且弹出面会以
//      destroy→create 换 id 的方式轮换重建（journal 中同秒 OFF→ON 重武装即其
//      形状）；无论卡片窗因何从某一轮扫描中缺席，都不能反推它"已消失"——
//      旧实现"未见两轮即删"把"扫不到"当成了"离场证据"，正是"避让几秒后自动
//      失效"振荡的通道；活性直查把释放判据与扫描可见性彻底解耦。
//      avoided 期间的 2s 定时器兜底，使"漏一条事件 = 面板永久隐藏"在结构上不可能。
//
// 对账成本控制（扩深度到 4 的前提）：逐层**批量** query_tree→attributes→
// WM_NAME/WM_CLASS 预筛（每窗 2 次属性往返），身份命中或本就建档者才补全量
// fetchIdentity（几何/位置）；窗数预算超限即停并告警。逐窗同步往返实测全树
// 10 秒量级，2 秒对账周期下不可接受。
//
// 释放防抖（对"避让几秒后自动失效"振荡回归的修复）：
//   * 进入避让（counted false→true）永远即时；
//   * 退出避让分两类：窗口的**权威离场**（该 id 的 Unmap/Destroy 事件、活性直查
//     判不可见/已销毁）即时释放；"身份/尺寸/几何/叠合判定翻否"这类可被一次瞬态
//     误读触发的解除，须连续两次独立观测（事件记 1/2 + 复核轮确认）才真正
//     uncount——单轮误读（如隐藏期面板矩形暂不可知、WM_NAME 一次空读、尺寸动画
//     中间帧低于阈值）不再能撤回避让；
//   * 面板矩形不可知时保持现状：fail-open 只挡"新避让"的建立，不撤"已避让"
//     （未知≠无冲突；面板隐藏期本就读不到自身窗口，未知是常态而非证据）；
//   * 身份读失败（空名）保留上一次成功读取的非空值（sticky identity）：
//     合法窗口的 WM_NAME 不会自己变成空，空只可能是瞬态读失败。
// 上述决策路径（ON/OFF/活性释放/滞留清理/快确认计数）以 qWarning 级输出：dde-shell
// 运行环境默认以 QT_LOGGING_RULES 关闭 info 级，qCInfo 的决策日志在线上不可见。
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

    // 立即按窗口树真值重建状态（清掉漏事件造成的滞留条目）。
    // 由面板在"用户要求显示"时调用，保证按显示按钮先对账再决定是否隐藏；
    // avoided 为真期间另有内部定时器定期调用。
    void recheck();

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
        // 释放防抖：非权威"解除冲突"的连续确认计数（见类注释）。0=无待确认；
        // 首次误读到 1，第二次仍解除才真正 uncount；任一帧恢复冲突即清零。
        int releasePending = 0;
    };

    void onEvents();
    // 把 xcb 内部队列里的事件全部取出处理（同步往返会掏空 fd，见类注释）
    void drainEvents();
    void handleEvent(xcb_generic_event_t *event);
    // 同步拉取标题/类名/几何（本地 socket 单次往返，映射事件低频）
    void fetchIdentity(xcb_window_t win, WinInfo &info);
    // 同步拉取该窗在 root 上的绝对左上角（translate_coordinates，含 reparent 偏移）
    void fetchRootPosition(xcb_window_t win, WinInfo &info);
    // 对该窗自身订阅 StructureNotify+PropertyChange：被 WM reparent 进
    // 装饰框后，root 不再收到其 Map/Unmap，唯有直接订阅才能继续跟踪
    void selectEvents(xcb_window_t win);
    // 身份命中（只看 WM_NAME / WM_CLASS，不看尺寸阈值）——对账预筛用：
    // 未读几何时 isTarget 的尺寸门槛恒假，不能用它做预筛判据。
    bool identityTarget(const WinInfo &info) const;
    bool isTarget(const WinInfo &info) const;
    // 本面板 root 绝对矩形（像素）：不可知时返回空 QRect
    QRect panelRect() const;
    // 目标窗是否与本面板矩形叠合（几何不可知时退化为 true=照旧避让）
    bool conflictsWithPanel(const WinInfo &info) const;
    // 重估全部在册窗口（面板矩形变化时用）
    void reevaluateAll();
    // 依 mapped + 目标判定 + 叠合判定翻转 counted，并刷新聚合状态。
    // authoritative=true（Unmap/Destroy、用户显式显示对账）即时释放；否则
    // 释放走双确认：confirmPass=true 只在"独立复核轮次"（reconcile/快确认）
    // 传入，事件驱动的评估恒 false——一次逻辑变更可能连着发多条 X 事件，
    // 若每条都计一次确认，双确认会退化，正是"避让几秒后自动失效"的来源。
    void evaluate(xcb_window_t win, bool authoritative = false,
                  bool confirmPass = false);
    void refreshAvoided();
    void setAvoided(bool avoided);
    // 启动/兜底对账：逐层批处理遍历窗口树（reconcileWalk）重建"见到"集合，
    // 再对"避让中但未见"的条目做活性直查（R6），清掉已销毁/不可见者、把仍可见者
    // 记为见到；最后统一复核评估。userRequested=true（用户按"显示"按钮触发的
    // recheck）时按权威路径评估：面板矩形暂不可知的避让条目也即刻释放，保证
    // 按钮总能召回面板。
    void reconcile(bool userRequested = false);
    // 逐层批量遍历 root 子树（深度 ≤kMaxScanDepth、窗数 ≤kWalkWindowBudget）：
    // 本层 query_tree → 下层 attributes → 命中身份/已建档者补 WM_NAME/WM_CLASS，
    // 全程只按层同步等待，不再逐窗往返。见到的窗补入 m_seen 并 selectEvents。
    void reconcileWalk();
    // 双确认释放：为待确认窗口安排一次快确认评估（首个挂定时器，重复调用幂等）
    void armReleaseConfirm();

    xcb_connection_t *m_conn = nullptr;
    xcb_window_t m_root = 0;
    QSocketNotifier *m_notifier = nullptr;
    QHash<xcb_window_t, WinInfo> m_windows;
    // 本轮对账见到的窗口（reconcile 用它清掉没见到的旧条目）
    QSet<xcb_window_t> m_seen;
    // avoided 期间的定期对账定时器：漏事件时最多滞留一个周期即自愈
    QTimer m_recheckTimer;
    // 双确认释放的快确认通道（单发 500ms，首个解除候选时挂起）
    QTimer m_releaseConfirmTimer;
    // 侧栏自身窗口与其最近一次有效矩形（root 像素）：窗口未映射/未 exposed
    // 期间（含正在避让时）用缓存值判定叠合，故缓存由 const 访问器惰性写入
    QPointer<QWindow> m_panel;
    mutable QRect m_panelRectCached;
    bool m_avoided = false;
};
