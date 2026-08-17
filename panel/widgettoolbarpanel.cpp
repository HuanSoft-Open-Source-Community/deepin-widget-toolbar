// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbarpanel.h"

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

#include <pluginfactory.h>

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QQuickWindow>
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

    // 读取持久化状态（默认显示 + 默认置顶，Vista 侧栏风格）
    m_config = DConfig::create("org.deepin.dde.shell", "org.deepin.ds.widgettoolbar");
    if (m_config && m_config->isValid()) {
        m_visible = m_config->value("visible", true).toBool();
        m_pinned = m_config->value("pinned", true).toBool();
        m_cardTransparent = m_config->value("cardTransparent", false).toBool();
    } else {
        qWarning() << "DConfig invalid, use defaults (visible=true, pinned=true, cardTransparent=false)";
    }

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

    // X11 窗口层级/几何守护：QML Window 根创建后绑定（hide/show 重建后
    // rootObjectChanged 再次触发重新 attach），详见 WindowGuard 注释
    m_windowGuard = new WindowGuard(this);
    m_windowGuard->setPinned(m_pinned);
    connect(this, &DApplet::rootObjectChanged, this, [this]() {
        m_windowGuard->attach(qobject_cast<QQuickWindow *>(rootObject()));
    });

    return true;
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

void WidgetToolbarPanel::setVisible(bool visible)
{
    if (m_visible == visible) {
        return;
    }
    m_visible = visible;
    if (m_config && m_config->isValid()) {
        m_config->setValue("visible", visible);
    }
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
    Q_EMIT pinnedChanged(pinned);
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
    Q_EMIT cardTransparentChanged(cardTransparent);
}

void WidgetToolbarPanel::toggle()
{
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
    Q_EMIT settingsRequested();
}

void WidgetToolbarPanel::showAbout()
{
    Q_EMIT aboutRequested();
}

void WidgetToolbarPanel::openAddWidget()
{
    Q_EMIT addWidgetRequested();
}

void WidgetToolbarPanel::autoArrange()
{
    if (m_widgetManager)
        m_widgetManager->autoArrangeAll();
    Q_EMIT autoArrangeRequested();
}

D_APPLET_CLASS(WidgetToolbarPanel)
#include "widgettoolbarpanel.moc"
