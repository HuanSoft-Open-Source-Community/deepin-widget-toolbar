// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QIcon>
#include <QWidget>

// dock 托盘区的小组件工具栏按钮：仅负责绘制（明暗主题图标 + 面板可见态高亮）。
//
// 点击显隐不在这里处理：dde-tray-loader 的 PluginItem 会给该控件套上
// itemPadding = 4 的内容边距（插件窗口因此为 24×24，控件本身仍固定 16×16），
// 控件若自行消费鼠标事件，四周留白区的点击就只落到 PluginItem 被丢弃
// （表现为"只能点中心图标区"）。因此本控件刻意不处理鼠标事件（默认忽略并冒泡给
// PluginItem），由插件的 itemCommand() 交任务栏统一点击，整格一致生效。
class TrayButton : public QWidget
{
    Q_OBJECT
public:
    explicit TrayButton(QWidget *parent = nullptr);

    // 订阅面板显隐信号并查询当前状态，同步按钮高亮
    void initDbus();

protected:
    void paintEvent(QPaintEvent *event) override;

private Q_SLOTS:
    void onPanelVisibleChanged(bool visible);

private:
    void updateIcon();

    QIcon m_icon;
    bool m_panelVisible = false;
};
