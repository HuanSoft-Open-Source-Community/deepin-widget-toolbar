// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetmodel.h"
#include "widgetmanager.h"

#include <QFileInfo>
#include <QIcon>
#include <QUrl>

// 把小组件 manifest 里的图标名解析为可被 Image.source 使用的 URL，
// 解析顺序：主题图标 → 小组件自带 icons/<图标名>.svg → dwtappicon 占位：
// - 已是路径/file:// 直接返回
// - 否则按 XDG 图标主题规范 <root>/<theme>/<category>/<size>/<name>.<ext>
//   在当前主题（QIcon::themeName()）下查找，再按同样结构查 hicolor 兜底；
//   category 取主题里常见的上下文目录，size 偏好 scalable 优先（矢量图可无损
//   缩放到任意显示尺寸，清晰度最好），其后按 48/32/24/22/16 等常规栅格尺寸
//   从大到小回退（大图标缩小仍清晰，小图标放大会糊）；
// - 主题未命中时查小组件自带图标 <小组件目录>/icons/<图标名>.svg（widgetDir
//   来自 WidgetInfo.dir：内置组件为 qrc 前缀 ":/widgets/<id>"，第三方组件为
//   绝对目录），命中即返回可直接作 Image.source 的 URL（qrc 前缀返回
//   "qrc:/..." 形式，本地目录返回 file:// URL）；
// - 仍未命中时回退到本面板 image provider（DesktopAppIconProvider，走
//   QIcon::fromTheme，支持 .dci、去 -symbolic 重试与占位回退），URL 格式与
//   DesktopApps::iconSource() 保持一致：image://dwtappicon/<百分号编码名>@24
static QString resolveIconSource(const QString &iconName, const QString &widgetDir)
{
    if (iconName.isEmpty())
        return {};
    if (iconName.startsWith(QLatin1Char('/')) || iconName.startsWith(QLatin1String("file:")))
        return iconName;

    const QStringList exts = { QStringLiteral("svg"), QStringLiteral("png"), QStringLiteral("xpm") };
    const QStringList categories = {
        QStringLiteral("actions"), QStringLiteral("apps"), QStringLiteral("devices"),
        QStringLiteral("places"), QStringLiteral("mimetypes"), QStringLiteral("categories"),
        QStringLiteral("status"), QStringLiteral("emblems"), QStringLiteral("emotes")
    };
    const QStringList sizes = {
        QStringLiteral("scalable"), QStringLiteral("48"), QStringLiteral("32"),
        QStringLiteral("24"), QStringLiteral("22"), QStringLiteral("16"),
        QStringLiteral("64"), QStringLiteral("96"), QStringLiteral("128")
    };
    const QStringList searchPaths = QIcon::themeSearchPaths();

    // 依次在当前主题与 hicolor 兜底主题下按 XDG 目录结构查找
    const QStringList themes = { QIcon::themeName(), QStringLiteral("hicolor") };
    for (const QString &theme : themes) {
        for (const QString &dir : searchPaths) {
            const QString themeBase = dir + QLatin1Char('/') + theme;
            for (const QString &category : categories) {
                for (const QString &size : sizes) {
                    const QString sizeBase = themeBase + QLatin1Char('/') + category
                        + QLatin1Char('/') + size;
                    for (const QString &ext : exts) {
                        const QString p = sizeBase + QLatin1Char('/') + iconName
                            + QLatin1Char('.') + ext;
                        if (QFileInfo::exists(p))
                            return QUrl::fromLocalFile(p).toString();
                    }
                }
            }
        }
    }

    // 主题查找未命中：尝试小组件自带图标 <小组件目录>/icons/<图标名>.svg
    // （QFileInfo::exists 对 ":/..." qrc 路径同样可用）
    if (!widgetDir.isEmpty()) {
        const QString bundled = widgetDir + QLatin1String("/icons/") + iconName
            + QLatin1String(".svg");
        if (QFileInfo::exists(bundled)) {
            // qrc 前缀目录返回 "qrc:/..." URL，本地目录返回 file:// URL
            if (widgetDir.startsWith(QLatin1Char(':')))
                return QStringLiteral("qrc:") + bundled.mid(1);
            return QUrl::fromLocalFile(bundled).toString();
        }
    }

    // 主题与自带图标均未命中：交给 image provider 走 QIcon::fromTheme 兜底
    const QString encoded = QString::fromUtf8(QUrl::toPercentEncoding(iconName));
    return QStringLiteral("image://dwtappicon/%1@24").arg(encoded);
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
        return resolveIconSource(w.icon, w.dir);
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
