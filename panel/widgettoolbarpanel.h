// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <panel.h>

#include <DConfig>

#include <QEvent>
#include <QPointer>

DS_USE_NAMESPACE
using Dtk::Core::DConfig;

class QQuickWindow;

class WidgetToolbarPanel : public DPanel
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.widgettoolbar")
    Q_PROPERTY(bool visible READ visible WRITE setVisible NOTIFY visibleChanged FINAL)
    Q_PROPERTY(bool pinned READ pinned WRITE setPinned NOTIFY pinnedChanged FINAL)
public:
    explicit WidgetToolbarPanel(QObject *parent = nullptr);
    ~WidgetToolbarPanel() override;

    bool load() override;
    bool init() override;

    bool visible() const;
    void setVisible(bool visible);
    bool pinned() const;
    void setPinned(bool pinned);

public Q_SLOTS:
    // 供 D-Bus（org.deepin.dde.widgettoolbar）与 QML 调用的显隐控制
    void toggle();
    void show();
    void hide();

Q_SIGNALS:
    void visibleChanged(bool visible);
    void pinnedChanged(bool pinned);

protected:
    // X11 下 LayerShellEmulation 的 LayerButtom 分支会用 setFlags() 整体替换窗口 flags
    // （清掉 Qt.Tool/Qt.FramelessWindowHint），且窗口重建后窗口类型属性丢失，都会让面板
    // 回落为普通窗口被 kwin 装饰出标题栏与窗口按钮。这里在窗口事件（显示/曝光/重建）
    // 与 layer 变化时强制恢复期望的 frameless flags，作为 QML 端 applyLayerFlags 的主兜底。
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void enforceFrameless();
    // QPointer：窗口可能在 hide/show 或屏幕变更时被重建销毁，避免裸指针悬垂
    QPointer<QQuickWindow> m_window;

    DConfig *m_config = nullptr;
    bool m_visible = true;
    bool m_pinned = true;
};
