// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbarpanel.h"

#include "debuglogger.h"
#include "panelavoidwatcher.h"
#include "windowguard.h"

#include "audiovisualizer.h"
#include "clocktime.h"
#include "fileio.h"
#include "lyricssource.h"
#include "mediaplayer.h"
#include "mediaplayerregistry.h"
#include "systeminfo.h"
#include "timezones.h"
#include "widgethost.h"
#include "widgetmanager.h"
#include "widgetmodel.h"

#include "desktopapps.h"

#include <pluginfactory.h>

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QQmlEngine>
#include <QtQml/qqml.h>

// D-Bus 服务：面板显隐与置顶状态通过 session bus 暴露给 dde-dock 托盘触发按钮
// （托盘插件运行在 trayplugin-loader fork 的独立进程中，跨进程唯一可靠通道）
static const char kDBusService[] = "org.deepin.dde.widgettoolbar";
static const char kDBusPath[] = "/org/deepin/dde/widgettoolbar";

WidgetToolbarPanel::WidgetToolbarPanel(QObject *parent)
    : DPanel(parent)
{
}

WidgetToolbarPanel::~WidgetToolbarPanel()
{
    // 注销 MMV 避让订阅（插件 stop/update 时不留残余匹配）
    QDBusConnection::sessionBus().disconnect(
        QString(), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"),
        QStringLiteral("MultitaskStateChanged"), this,
        SLOT(onMultitaskStateChanged(bool)));
    delete m_config;
}

bool WidgetToolbarPanel::load()
{
    return DPanel::load();
}

bool WidgetToolbarPanel::init()
{
    DPanel::init();

    // 小组件宿主：扫描内置/第三方小组件、加载已添加实例清单
    m_widgetManager = new WidgetManager(this);
    m_widgetManager->init();
    m_widgetListModel = new WidgetListModel(m_widgetManager, this);
    m_widgetListModel->refresh();

    // 宿主能力代理（开放接口的一部分）：注册 QML 单例，小组件通过
    // import org.deepin.widgettoolbar 1.0 使用 FileIO / SystemInfo / Lyrics /
    // Timezones / ClockTime / WidgetHost
    auto *fileIO = new FileIO(this);
    fileIO->setAllowedRoot(m_widgetManager->widgetsDataRoot());
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "FileIO", fileIO);
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "SystemInfo", new SystemInfo(this));
    // 端闱乐部歌词代理：小组件通过它读取歌词
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "Lyrics", new LyricsSource(this));
    // MPRIS 播放器注册表与代理：播放控制器小组件通过它们枚举、订阅与控制播放器
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "MediaPlayers",
                                 new MediaPlayers(this));
    qmlRegisterType<MediaPlayer>("org.deepin.widgettoolbar", 1, 0, "MediaPlayer");
    // 时区数据代理：小组件通过它读取控制中心“时间设置”的时区列表与地区名
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "Timezones", new Timezones(this));
    // 预加载时间源：时钟/世界时钟共享同一整秒广播，避免大量表盘各自建 Timer 卡顿
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "ClockTime", new ClockTime(this));
    // 配置回写代理：小组件经它持久化自身实例配置（如世界时间的缩放补位）
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "WidgetHost",
                                 new WidgetHost(m_widgetManager, this));
    // 系统音频频谱代理：频谱面板经它读取默认 sink monitor 回环的 32 带频谱，
    // 内部在独立线程采集（dlopen libpulse），仅输出只读数值，绝不触麦克风
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "AudioVisualizer",
                                 new AudioVisualizer(this));
    // 桌面程序条目代理：应用快捷启动器经它取条目、解析默认程序与启动应用。
    // 注意条目枚举**始终**来自目录扫描（见 desktopapps.cpp 的 fallbackApplicationsDirs），
    // ApplicationManager1 只影响 launch() 的启动通道（不可用时降级直执行 Exec）；
    // 图标经 image provider（dwtappicon）与 dde-shell 同源渲染。
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "DesktopApps",
                                 new DesktopApps(this));

    // 读取持久化状态（默认显示 + 默认置顶，Vista 侧栏风格）
    m_config = DConfig::create("org.deepin.dde.shell", "org.deepin.ds.widgettoolbar");
    if (m_config && m_config->isValid()) {
        m_visible = m_config->value("visible", true).toBool();
        m_pinned = m_config->value("pinned", true).toBool();
        m_cardTransparent = m_config->value("cardTransparent", false).toBool();
        m_showCardNames = m_config->value("showCardNames", true).toBool();
    } else {
        qWarning() << "DConfig invalid, use defaults (visible=true, pinned=true,"
                      " cardTransparent=false, showCardNames=true)";
    }

    // 调试模式：缺省关闭，只有开启时 DebugLogger 才向磁盘写日志（见 debuglogger.cpp）。
    // 与上面同一份 m_config 取值，故放在其之后、D-Bus 注册之前，不打乱原有语句次序。
    m_debugMode = m_config && m_config->isValid()
                      ? m_config->value("debugMode", false).toBool()
                      : false;
    DebugLogger::instance()->setEnabled(m_debugMode);
    if (m_config) {
        // 开关经 QML/外部工具改动后即时生效，无需重启面板
        connect(m_config, &DConfig::valueChanged, this, [this](const QString &key) {
            if (key != QLatin1String("debugMode"))
                return;
            const bool enabled = m_config->value(key, false).toBool();
            if (m_debugMode == enabled)
                return;
            m_debugMode = enabled;
            // 顺序：开启时先启用再写日志；关闭时必须先写日志再关（DEBUG_LOG 会被
            // isEnabled() 拦掉，否则"切到关闭"这条永远不会落盘）。
            if (m_debugMode) {
                DebugLogger::instance()->setEnabled(true);
                DEBUG_LOG(panel, QStringLiteral("debug mode switched on"));
            } else {
                DebugLogger::instance()->log(DebugLogger::Level::Info,
                                             QStringLiteral("panel"),
                                             QStringLiteral("debug mode switched off"));
                DebugLogger::instance()->setEnabled(false);
            }
            Q_EMIT debugModeChanged(m_debugMode);
        });
    }
    DEBUG_LOG(panel, QString("panel init: debugMode=%1, visible=%2, pinned=%3, "
                             "cardTransparent=%4, showCardNames=%5")
                         .arg(m_debugMode)
                         .arg(m_visible)
                         .arg(m_pinned)
                         .arg(m_cardTransparent)
                         .arg(m_showCardNames));

    // 注册 D-Bus 服务，供托盘触发按钮控制显隐
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(kDBusService)) {
        qWarning() << "D-Bus registerService failed:" << bus.lastError().message();
    } else {
        bus.registerObject(kDBusPath, this,
                           QDBusConnection::ExportAllSlots
                               | QDBusConnection::ExportAllSignals
                               | QDBusConnection::ExportAllProperties);
    }

    // 外部面板避让（X11）：通知/通知中心/控制中心/电源/剪贴板/托盘快捷面板
    // 与展开小卡等**几何与本侧栏叠合**时临时隐藏侧栏，关闭/移开自动恢复。
    // panelAvoided 直接转发 watcher 的 avoided（信号对信号连接，无本地副本），
    // QML 端与 MMV 避让并列使用；Wayland 下 watcher start 即静默，属性恒 false。
    // 需在 rootObjectChanged 之前创建：下面的 lambda 要把面板自身窗口交给
    // watcher 做叠合判定（hide/show 重建窗口后重新 attach）。
    m_panelAvoidWatcher = new PanelAvoidWatcher(this);
    connect(m_panelAvoidWatcher, &PanelAvoidWatcher::avoidedChanged,
            this, &WidgetToolbarPanel::panelAvoidedChanged);
    m_panelAvoidWatcher->start();

    // X11 窗口层级/几何守护：QML Window 根创建后绑定（hide/show 重建后
    // rootObjectChanged 再次触发重新 attach），详见 WindowGuard 注释
    m_windowGuard = new WindowGuard(this);
    m_windowGuard->setPinned(m_pinned);
    connect(this, &DApplet::rootObjectChanged, this, [this]() {
        auto *window = qobject_cast<QQuickWindow *>(rootObject());
        if (window) {
            // 应用图标 image provider（小组件 Image source 形如
            // "image://dwtappicon/<图标名或路径>@<像素>"）：QML 引擎就绪后注册一次。
            // 每个小组件根对象由该引擎创建，注册必须先于任何图标请求。
            if (QQmlEngine *engine = qmlEngine(window); engine && engine != m_iconEngine) {
                engine->addImageProvider(QStringLiteral("dwtappicon"),
                                         DesktopApps::createIconProvider());
                m_iconEngine = engine;
            }
        }
        m_windowGuard->attach(window);
        // 避让叠合判定需要侧栏自身矩形；rootObject 非 QQuickWindow 时为
        // nullptr，attachPanel 据此解除绑定
        m_panelAvoidWatcher->attachPanel(window);
    });

    // 多任务视图避让（kwin multitaskview 特效对 Dock/Notification 类型窗口不经缩略图
    // 收录、也不隐藏，直接绘制在概览之上——面板置顶=Notification/置底=Dock 恰命中，
    // 两种模式都不避让。与任务栏 DockHelper 同源，监听特效 setActive 发出的
    // MultitaskStateChanged，进入 MMV 临时隐藏窗口、退出自动恢复）
    watchMultitaskView();

    return true;
}

void WidgetToolbarPanel::onMultitaskStateChanged(bool active)
{
    // 记下"信号已到"：watchMultitaskView() 的异步初始态应答据此让位（见该函数）
    m_multitaskSignalSeen = true;
    setMultitaskAvoided(active);
}

void WidgetToolbarPanel::watchMultitaskView()
{
    // 信号由特效 setActive 无条件发出，覆盖 dock 按钮（com.deepin.wm ShowWorkspace）、
    // Meta+S 全局快捷键、触摸板手势等全部唤起路径，且 X11 / Wayland 行为一致。
    // service 传空串匹配任意发送者（与 dde-shell DockHelper 用法一致）。
    QDBusConnection::sessionBus().connect(
        QString(), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"),
        QStringLiteral("MultitaskStateChanged"), this,
        SLOT(onMultitaskStateChanged(bool)));

    // 初始态对账：宿主可能在 MMV 开启期间重启（错过 true 事件）。dde-fakewm
    // 经同一信号缓存了该状态，异步查询一次；服务缺失/失败则静默保持 false。
    QDBusMessage query = QDBusMessage::createMethodCall(
        QStringLiteral("com.deepin.wm"), QStringLiteral("/com/deepin/wm"),
        QStringLiteral("com.deepin.wm"), QStringLiteral("GetMultiTaskingStatus"));
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(query), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
                // 应答只用于补齐"错过的 true 事件"：若查询往返期间已经收到过
                // MultitaskStateChanged（用户恰好此时开关视图），迟到的旧应答
                // 会覆盖更新的信号值，故有信号在先就丢弃这次应答。
                if (!w->isError() && !m_multitaskSignalSeen) {
                    const QList<QVariant> args = w->reply().arguments();
                    if (!args.isEmpty())
                        setMultitaskAvoided(args.first().toBool());
                }
                w->deleteLater();
            });
}

bool WidgetToolbarPanel::visible() const
{
    return m_visible;
}

WidgetManager *WidgetToolbarPanel::widgetManager() const
{
    return m_widgetManager;
}

WidgetListModel *WidgetToolbarPanel::widgetListModel() const
{
    return m_widgetListModel;
}

QQuickWindow *WidgetToolbarPanel::rootWindow() const
{
    return qobject_cast<QQuickWindow *>(rootObject());
}

void WidgetToolbarPanel::setVisible(bool visible)
{
    if (m_visible == visible) {
        return;
    }
    m_visible = visible;
    if (m_config && m_config->isValid()) {
        m_config->setValue("visible", visible);
    }
    // 用户要求显示面板时，先按窗口树真值对账一次：避让状态若因漏事件而滞留，
    // 面板会一直不显示且用户无法自救；此刻立即纠正，保证显示按钮永远有效。
    const bool rechecked = visible && m_panelAvoidWatcher;
    if (rechecked) {
        m_panelAvoidWatcher->recheck();
    }
    // 显隐是排查"面板不见了"的第一现场：记下用户意图、是否已对账、以及此刻
    // 两个避让量的实际值——三者合起来才能判定窗口为何最终没露出来。
    DEBUG_LOG(panel, QStringLiteral("visible -> %1 (recheck=%2, multitaskAvoided=%3, "
                                    "panelAvoided=%4, watcher=%5)")
                         .arg(visible)
                         .arg(rechecked)
                         .arg(m_multitaskAvoided)
                         .arg(panelAvoided())
                         .arg(m_panelAvoidWatcher ? "alive" : "null"));
    Q_EMIT visibleChanged(visible);
}

bool WidgetToolbarPanel::pinned() const
{
    return m_pinned;
}

void WidgetToolbarPanel::setPinned(bool pinned)
{
    if (m_pinned == pinned) {
        return;
    }
    m_pinned = pinned;
    if (m_config && m_config->isValid()) {
        m_config->setValue("pinned", pinned);
    }
    if (m_windowGuard)
        m_windowGuard->setPinned(pinned);
    // 置顶改变窗口类型（Notification/Dock），会连带影响 kwin 与避让判定，值得留痕
    DEBUG_LOG(panel, QStringLiteral("pinned -> %1 (windowGuard=%2)")
                         .arg(pinned)
                         .arg(m_windowGuard ? "alive" : "null"));
    Q_EMIT pinnedChanged(pinned);
}

bool WidgetToolbarPanel::multitaskAvoided() const
{
    return m_multitaskAvoided;
}

bool WidgetToolbarPanel::panelAvoided() const
{
    return m_panelAvoidWatcher && m_panelAvoidWatcher->avoided();
}

QString WidgetToolbarPanel::appVersion() const
{
    // WIDGETTOOLBAR_VERSION 由 panel/CMakeLists.txt 从工程 PROJECT_VERSION 注入；
    // 万一构建系统没定义（例如被别的工程直接编译本文件），退回 "unknown" 而不是
    // 编译失败，也不在 QML 侧再维护一份会过期的常量。
#ifdef WIDGETTOOLBAR_VERSION
    return QStringLiteral(WIDGETTOOLBAR_VERSION);
#else
    return QStringLiteral("unknown");
#endif
}

void WidgetToolbarPanel::setMultitaskAvoided(bool avoided)
{
    if (m_multitaskAvoided == avoided)
        return;
    m_multitaskAvoided = avoided;
    // 刻意不触碰 m_visible/DConfig/托盘高亮：避让是临时视觉态，
    // 用户显隐语义（含重启恢复）保持不变，退出 MMV 后自动回来
    // 跃变日志：面板"自己不见了"的另一大来源，且此路径不经 setVisible，无它即无痕迹
    DEBUG_LOG(panel, QStringLiteral("multitaskAvoided -> %1 (kwin MultitaskStateChanged)").arg(avoided));
    Q_EMIT multitaskAvoidedChanged(avoided);
}

bool WidgetToolbarPanel::cardTransparent() const
{
    return m_cardTransparent;
}

void WidgetToolbarPanel::setCardTransparent(bool cardTransparent)
{
    if (m_cardTransparent == cardTransparent) {
        return;
    }
    m_cardTransparent = cardTransparent;
    if (m_config && m_config->isValid()) {
        m_config->setValue("cardTransparent", cardTransparent);
    }
    DEBUG_LOG(panel, QStringLiteral("cardTransparent -> %1").arg(cardTransparent));
    Q_EMIT cardTransparentChanged(cardTransparent);
}

// 卡片名称显示：全局唯一开关，刻意没有按实例的读写接口（避免面板出现每卡各自
// 的显隐状态）。开启时由**格高变高**让出名称空间、卡片宽度保持不变（见 main.qml
// 的 cardLabelHeight/cardLabelShrink/cardSpacingY），多行卡片随之相应变高。
bool WidgetToolbarPanel::showCardNames() const
{
    return m_showCardNames;
}

void WidgetToolbarPanel::setShowCardNames(bool showCardNames)
{
    if (m_showCardNames == showCardNames) {
        return;
    }
    m_showCardNames = showCardNames;
    if (m_config && m_config->isValid()) {
        m_config->setValue("showCardNames", showCardNames);
    }
    DEBUG_LOG(panel, QStringLiteral("showCardNames -> %1").arg(showCardNames));
    Q_EMIT showCardNamesChanged(showCardNames);
}

void WidgetToolbarPanel::toggle()
{
    // 先对账再翻转：托盘按钮是用户唯一的显隐入口，若面板此刻正被滞留的避让态
    // 隐藏（visible 已是 true，表达式 visible && !panelAvoided 恒假），这一次
    // 点击就应把面板叫回来，而不是被翻成"隐藏"再点第二次。
    DEBUG_LOG(panel, QStringLiteral("toggle() from tray/D-Bus (current visible=%1)").arg(m_visible));
    if (m_panelAvoidWatcher) {
        m_panelAvoidWatcher->recheck();
    }
    setVisible(!m_visible);
}

void WidgetToolbarPanel::show()
{
    setVisible(true);
}

void WidgetToolbarPanel::hide()
{
    setVisible(false);
}

void WidgetToolbarPanel::openSettings()
{
    DEBUG_LOG(panel, "openSettings() via D-Bus");
    Q_EMIT settingsRequested();
}

void WidgetToolbarPanel::showAbout()
{
    DEBUG_LOG(panel, "showAbout() via D-Bus");
    Q_EMIT aboutRequested();
}

void WidgetToolbarPanel::openAddWidget()
{
    DEBUG_LOG(panel, "openAddWidget() via D-Bus");
    Q_EMIT addWidgetRequested();
}

void WidgetToolbarPanel::autoArrange()
{
    DEBUG_LOG(panel, QStringLiteral("autoArrange() via D-Bus (manager=%1)")
                         .arg(m_widgetManager ? "alive" : "null"));
    if (m_widgetManager)
        m_widgetManager->autoArrangeAll();
    Q_EMIT autoArrangeRequested();
}

bool WidgetToolbarPanel::debugMode() const
{
    return m_debugMode;
}

// 调试模式开关：与其余面板级开关同范式——先持久化、后发信号，QML 侧只读写
// Panel.debugMode，实际是否落盘由 DebugLogger 内部的 enabled 门决定。
void WidgetToolbarPanel::setDebugMode(bool debugMode)
{
    if (m_debugMode == debugMode) {
        return;
    }
    m_debugMode = debugMode;
    if (m_config && m_config->isValid()) {
        m_config->setValue("debugMode", debugMode);
    }
    // 顺序：开启时先启用再写日志；关闭时必须先写日志再关——DEBUG_LOG 会先判
    // isEnabled()，关闭时该值已为假，那条记录会永远不落盘。
    if (debugMode) {
        DebugLogger::instance()->setEnabled(true);
        DEBUG_LOG(panel, QStringLiteral("debugMode -> 1"));
    } else {
        DebugLogger::instance()->log(DebugLogger::Level::Info,
                                     QStringLiteral("panel"),
                                     QStringLiteral("debugMode -> 0"));
        DebugLogger::instance()->setEnabled(false);
    }
    Q_EMIT debugModeChanged(debugMode);
}

D_APPLET_CLASS(WidgetToolbarPanel)
#include "widgettoolbarpanel.moc"
