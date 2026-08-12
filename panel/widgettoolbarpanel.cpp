// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbarpanel.h"

#include <dlayershellwindow.h>
#include <pluginfactory.h>

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQuickWindow>
#include <QTimer>

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
        }
        enforceFrameless();
    });

    return true;
}

// 期望 flags 与 QML 端 applyLayerFlags 保持一致：置底时保留 WindowStaysOnBottomHint。
// 仅在 xcb 平台需要（Wayland 下 layer-shell 窗口由合成器管理，无标题栏问题）。
void WidgetToolbarPanel::enforceFrameless()
{
    if (!m_window || QGuiApplication::platformName() != "xcb") {
        return;
    }
    Qt::WindowFlags desired = Qt::Tool | Qt::FramelessWindowHint;
    if (!m_pinned) {
        desired |= Qt::WindowStaysOnBottomHint;
    }
    if (m_window->flags() != desired) {
        m_window->setFlags(desired);
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

D_APPLET_CLASS(WidgetToolbarPanel)
#include "widgettoolbarpanel.moc"
