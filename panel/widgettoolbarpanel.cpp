// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgettoolbarpanel.h"

#include <pluginfactory.h>

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

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
    return true;
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
