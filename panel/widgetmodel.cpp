// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetmodel.h"
#include "widgetmanager.h"

#include <QFileInfo>
#include <QIcon>
#include <QUrl>

// 把小组件 manifest 里的图标名解析为可被 Image.source 使用的文件 URL：
// - 已是路径/file:// 直接返回
// - 否则按 QIcon 主题搜索路径（当前主题 + hicolor 兜底）查找常见扩展名
static QString resolveIconSource(const QString &iconName)
{
    if (iconName.isEmpty())
        return {};
    if (iconName.startsWith(QLatin1Char('/')) || iconName.startsWith(QLatin1String("file:")))
        return iconName;

    const QStringList exts = { QStringLiteral("svg"), QStringLiteral("png"), QStringLiteral("xpm") };
    const QStringList searchPaths = QIcon::themeSearchPaths();
    const QString theme = QIcon::themeName();
    for (const QString &dir : searchPaths) {
        const QString base = dir + QLatin1Char('/') + theme;
        for (const QString &ext : exts) {
            const QString p = base + QLatin1Char('/') + iconName + QLatin1Char('.') + ext;
            if (QFileInfo::exists(p))
                return QUrl::fromLocalFile(p).toString();
        }
    }
    for (const QString &dir : searchPaths) {
        for (const QString &ext : exts) {
            const QString p = dir + QStringLiteral("/hicolor/") + iconName + QLatin1Char('.') + ext;
            if (QFileInfo::exists(p))
                return QUrl::fromLocalFile(p).toString();
        }
    }
    return {};
}

WidgetListModel::WidgetListModel(WidgetManager *manager, QObject *parent)
    : QAbstractListModel(parent)
    , m_manager(manager)
{
    if (m_manager) {
        connect(m_manager, &WidgetManager::widgetsChanged, this, &WidgetListModel::refresh);
        connect(m_manager, &WidgetManager::instancesChanged, this, &WidgetListModel::refresh);
    }
}

int WidgetListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid() || !m_manager)
        return 0;
    return m_manager->availableWidgets().size();
}

QVariant WidgetListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || !m_manager)
        return QVariant();

    const QList<WidgetManager::WidgetInfo> widgets = m_manager->availableWidgets();
    if (index.row() < 0 || index.row() >= widgets.size())
        return QVariant();
    const WidgetManager::WidgetInfo &w = widgets.at(index.row());

    switch (role) {
    case WidgetIdRole:
        return w.id;
    case NameRole:
        return w.name;
    case IconRole:
        return resolveIconSource(w.icon);
    case DescriptionRole:
        return w.description;
    case ColsRole:
        return w.defaultSize.width();
    case RowsRole:
        return w.defaultSize.height();
    case BuiltinRole:
        return w.builtin;
    case InstalledRole:
        return m_manager->isInstalled(w.id);
    default:
        break;
    }
    return QVariant();
}

QHash<int, QByteArray> WidgetListModel::roleNames() const
{
    return {
        { WidgetIdRole, "widgetId" },
        { NameRole, "name" },
        { IconRole, "icon" },
        { DescriptionRole, "description" },
        { ColsRole, "cols" },
        { RowsRole, "rows" },
        { BuiltinRole, "builtin" },
        { InstalledRole, "installed" },
    };
}

void WidgetListModel::refresh()
{
    beginResetModel();
    endResetModel();
}
