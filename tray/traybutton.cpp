// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "traybutton.h"

#include <DGuiApplicationHelper>

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusServiceWatcher>
#include <QMouseEvent>
#include <QPainter>

DGUI_USE_NAMESPACE

// 与面板（org.deepin.ds.widgettoolbar DPanel）对应的 D-Bus 服务
static const QString kDBusService = QStringLiteral("org.deepin.dde.widgettoolbar");
static const QString kDBusPath = QStringLiteral("/org/deepin/dde/widgettoolbar");
static const QString kDBusInterface = QStringLiteral("org.deepin.dde.widgettoolbar");

TrayButton::TrayButton(QWidget *parent)
    : QWidget(parent)
{
    setAccessibleName(QStringLiteral("WidgetToolbarButton"));
    setToolTip(tr("Widget Toolbar"));

    // 按系统主题选择图标：亮主题用深色图标（-dark），暗主题用浅色图标
    updateIcon();
    connect(DGuiApplicationHelper::instance(), &DGuiApplicationHelper::themeTypeChanged,
            this, [this]() { updateIcon(); });
}

void TrayButton::updateIcon()
{
    const bool darkTheme = DGuiApplicationHelper::instance()->themeType()
        == DGuiApplicationHelper::DarkType;
    m_icon = QIcon(darkTheme ? QStringLiteral(":/icons/widget-toolbar.svg")
                             : QStringLiteral(":/icons/widget-toolbar-dark.svg"));
    update();
}

void TrayButton::initDbus()
{
    // 监听面板服务上线/下线，更新按钮可用状态
    m_watcher = new QDBusServiceWatcher(kDBusService, QDBusConnection::sessionBus(),
                                        QDBusServiceWatcher::WatchForRegistration
                                            | QDBusServiceWatcher::WatchForUnregistration,
                                        this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered,
            this, &TrayButton::onServiceAvailable);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &TrayButton::onServiceUnavailable);

    // 订阅面板显隐变化信号，同步按钮高亮
    QDBusConnection::sessionBus().connect(kDBusService, kDBusPath, kDBusInterface,
                                          QStringLiteral("visibleChanged"),
                                          this, SLOT(onPanelVisibleChanged(bool)));

    // 查询面板当前显隐状态
    QDBusInterface iface(kDBusService, kDBusPath, kDBusInterface);
    if (iface.isValid()) {
        onPanelVisibleChanged(iface.property("visible").toBool());
        m_serviceAvailable = true;
    }
}

void TrayButton::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event)
    QPainter p(this);
    p.setRenderHint(QPainter::SmoothPixmapTransform);

    // 背景：hover 轻高亮，面板可见时强调色高亮
    if (m_hover || m_panelVisible) {
        QColor bg = palette().highlight().color();
        bg.setAlphaF(m_panelVisible ? 0.30 : 0.12);
        p.setPen(Qt::NoPen);
        p.setBrush(bg);
        p.drawRoundedRect(rect(), 6, 6);
    }

    // 图标：SVG 自带主题适配色（亮主题深色 / 暗主题浅色）
    const qreal dpr = devicePixelRatioF();
    const QSize pmSize = rect().size() * dpr;
    QPixmap pm(pmSize);
    pm.setDevicePixelRatio(dpr);
    pm.fill(Qt::transparent);
    QPainter pp(&pm);
    m_icon.paint(&pp, QRect(QPoint(0, 0), rect().size()));
    pp.end();
    p.drawPixmap(rect(), pm);
}

void TrayButton::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        togglePanel();
        event->accept();
        return;
    }
    QWidget::mousePressEvent(event);
}

void TrayButton::enterEvent(QEnterEvent *event)
{
    m_hover = true;
    update();
    QWidget::enterEvent(event);
}

void TrayButton::leaveEvent(QEvent *event)
{
    m_hover = false;
    update();
    QWidget::leaveEvent(event);
}

void TrayButton::onPanelVisibleChanged(bool visible)
{
    if (m_panelVisible == visible) {
        return;
    }
    m_panelVisible = visible;
    update();
}

void TrayButton::onServiceAvailable(const QString &service)
{
    Q_UNUSED(service)
    m_serviceAvailable = true;
    update();
}

void TrayButton::onServiceUnavailable(const QString &service)
{
    Q_UNUSED(service)
    m_serviceAvailable = false;
    update();
}

void TrayButton::togglePanel()
{
    if (!m_serviceAvailable) {
        qWarning() << "widget-toolbar panel D-Bus service is not available";
        return;
    }
    QDBusInterface iface(kDBusService, kDBusPath, kDBusInterface);
    if (!iface.isValid()) {
        qWarning() << "widget-toolbar D-Bus interface invalid";
        return;
    }
    iface.call(QStringLiteral("toggle"));
}

void TrayButton::updateAvailability()
{
    update();
}
