// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbarpanel.h"

#include "fileio.h"
#include "lyricssource.h"
#include "systeminfo.h"
#include "widgetmanager.h"
#include "widgetmodel.h"

#include <dlayershellwindow.h>
#include <pluginfactory.h>

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QScreen>
#include <QQuickWindow>
#include <QTimer>
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
    // import org.deepin.widgettoolbar 1.0 使用 FileIO / SystemInfo / Lyrics
    auto *fileIO = new FileIO(this);
    fileIO->setAllowedRoot(m_widgetManager->widgetsDataRoot());
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "FileIO", fileIO);
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "SystemInfo", new SystemInfo(this));
    // 端闱乐部歌词代理：唯一的系统 D-Bus 能力，小组件通过它读取歌词
    qmlRegisterSingletonInstance("org.deepin.widgettoolbar", 1, 0, "Lyrics", new LyricsSource(this));

    // 读取持久化状态（默认显示 + 默认置顶，Vista 侧栏风格）
    m_config = DConfig::create("org.deepin.dde.shell", "org.deepin.ds.widgettoolbar");
    if (m_config && m_config->isValid()) {
        m_visible = m_config->value("visible", true).toBool();
        m_pinned = m_config->value("pinned", true).toBool();
    } else {
        qWarning() << "DConfig invalid, use defaults (visible=true, pinned=true)";
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
        if (++m_geometryTicks > 20)
            m_geometryTimer.stop();
    });

    // X11 下标题栏兜底：QML Window 根创建后监听其事件与 layer 变化，
    // 强制恢复 frameless flags（详见 enforceFrameless 注释）
    connect(this, &DApplet::rootObjectChanged, this, [this]() {
        auto *win = qobject_cast<QQuickWindow *>(rootObject());
        if (!win || win == m_window) {
            return;
        }
        if (m_window) {
            m_window->removeEventFilter(this);
        }
        m_window = win;
        m_window->installEventFilter(this);
        if (auto *shell = DLayerShellWindow::get(m_window)) {
            connect(shell, &DLayerShellWindow::layerChanged, this, &WidgetToolbarPanel::enforceFrameless);
            // X11 下边距由 0 变为正确值后，模拟层可能不按最新边距重放窗口几何，
            // 这里监听边距变化直接重算锚定几何（enforceFrameless 内部仅 xcb 生效）。
            connect(shell, &DLayerShellWindow::marginsChanged, this, &WidgetToolbarPanel::enforceFrameless);
        }
        enforceFrameless();
        m_geometryTicks = 0;
        m_geometryTimer.start();
    });

    return true;
}

// 期望 flags 与 QML 端 applyLayerFlags 保持一致：置顶时 WindowStaysOnTopHint，
// 置底时 WindowStaysOnBottomHint。仅在 xcb 平台需要（Wayland 下 layer-shell
// 窗口由合成器管理；X11 下 LayerShellEmulation 的 layer 映射在窗口 hide/show
// 重建原生窗口后不会重新应用，故层级完全由这里恢复的 flags 保证）。
void WidgetToolbarPanel::enforceFrameless()
{
    if (!m_window || QGuiApplication::platformName() != "xcb") {
        return;
    }
    Qt::WindowFlags desired = Qt::Tool | Qt::FramelessWindowHint;
    desired |= m_pinned ? Qt::WindowStaysOnTopHint : Qt::WindowStaysOnBottomHint;
    if (m_window->flags() != desired) {
        m_window->setFlags(desired);
    }
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

bool WidgetToolbarPanel::eventFilter(QObject *watched, QEvent *event)
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
            QTimer::singleShot(0, this, &WidgetToolbarPanel::enforceFrameless);
            break;
        case QEvent::Expose:
            QTimer::singleShot(0, this, &WidgetToolbarPanel::enforceFrameless);
            break;
        case QEvent::PlatformSurface: {
            auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
            if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
                QTimer::singleShot(0, this, &WidgetToolbarPanel::enforceFrameless);
            }
            break;
        }
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
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
    Q_EMIT pinnedChanged(pinned);
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
