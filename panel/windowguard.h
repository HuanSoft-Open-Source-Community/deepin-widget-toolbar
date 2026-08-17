// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QTimer>

class QQuickWindow;

// 面板窗口的层级与几何守护（从 WidgetToolbarPanel 拆分）：
// X11 下 LayerShellEmulation 的 LayerButtom 分支会用 setFlags() 整体替换窗口
// flags（清掉 Qt.Tool/Qt.FramelessWindowHint），且窗口重建后窗口类型属性丢失，
// 都会让面板回落为普通窗口被 kwin 装饰出标题栏与窗口按钮。本类在窗口事件
// （显示/曝光/重建）与 layer 变化时强制恢复期望的 frameless flags，并短轮询
// 校准窗口几何。Wayland 下全部为无操作。
class WindowGuard : public QObject
{
    Q_OBJECT
public:
    explicit WindowGuard(QObject *parent = nullptr);

    // 绑定（或重新绑定）窗口：安装事件过滤器并监听 layer/边距变化；
    // 窗口 hide/show 或屏幕变更重建后由宿主再次调用
    void attach(QQuickWindow *window);
    // 同步面板置顶状态（决定恢复的 flags）
    void setPinned(bool pinned);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void enforceFrameless();

    QQuickWindow *m_window = nullptr;
    bool m_pinned = true;
    // X11 下按当前边距短轮询校准窗口几何，覆盖 hide/show 重建、screen 迟到等
    // 事件错位场景（约 5s 后自动停止）；Wayland 不启动。
    QTimer m_geometryTimer;
    int m_geometryTicks = 0;
};
