// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "windowguard.h"

#include <dlayershellwindow.h>
#include <dsglobal.h>

DS_USE_NAMESPACE

#include <QDebug>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQuickWindow>
#include <QScreen>

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
        if (++m_geometryTicks > 20)
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

// 期望 flags 与 QML 端 applyLayerFlags 保持一致：置顶时 WindowStaysOnTopHint，
// 置底时 WindowStaysOnBottomHint。仅在 xcb 平台需要（Wayland 下 layer-shell
// 窗口由合成器管理；X11 下 LayerShellEmulation 的 layer 映射在窗口 hide/show
// 重建原生窗口后不会重新应用，故层级完全由这里恢复的 flags 保证）。
void WindowGuard::enforceFrameless()
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
                QTimer::singleShot(0, this, &WindowGuard::enforceFrameless);
            }
            break;
        }
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}
