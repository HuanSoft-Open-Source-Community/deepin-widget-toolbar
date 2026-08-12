// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <panel.h>

#include <DConfig>

DS_USE_NAMESPACE
using Dtk::Core::DConfig;

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

private:
    DConfig *m_config = nullptr;
    bool m_visible = true;
    bool m_pinned = true;
};
