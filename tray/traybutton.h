// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QIcon>
#include <QWidget>

class QDBusServiceWatcher;

// dock 托盘区的小组件工具栏触发按钮：
// 点击通过 session bus D-Bus 切换侧栏面板显隐，并监听面板 visibleChanged 信号同步高亮状态
class TrayButton : public QWidget
{
    Q_OBJECT
public:
    explicit TrayButton(QWidget *parent = nullptr);

    void initDbus();

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void enterEvent(QEnterEvent *event) override;
    void leaveEvent(QEvent *event) override;

private Q_SLOTS:
    void onPanelVisibleChanged(bool visible);
    void onServiceAvailable(const QString &service);
    void onServiceUnavailable(const QString &service);

private:
    void togglePanel();
    void updateAvailability();
    void updateIcon();

    QIcon m_icon;
    bool m_hover = false;
    bool m_panelVisible = false;
    bool m_serviceAvailable = false;
    QDBusServiceWatcher *m_watcher = nullptr;
};
