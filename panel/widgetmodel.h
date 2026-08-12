// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QAbstractListModel>

class WidgetManager;

// 供"添加小组件"面板使用的列表模型：
// 每一项对应一个可添加的小组件（内置 + 已安装第三方），
// installed 角色反映其是否已添加实例。
class WidgetListModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        WidgetIdRole = Qt::UserRole + 1,
        NameRole,
        IconRole,
        DescriptionRole,
        ColsRole,
        RowsRole,
        BuiltinRole,
        InstalledRole,
    };

    explicit WidgetListModel(WidgetManager *manager, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void refresh();

private:
    WidgetManager *m_manager = nullptr;
};
