// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QSize>
#include <QString>
#include <QVariantList>

// 小组件宿主共享的基础数据类型：
// WidgetInfo（manifest 静态元数据）与 WidgetInstance（已添加实例）。
// 作为依赖最底层，WidgetManager / WidgetGrid / WidgetPackage 等模块复用，
// 避免各模块互相包含形成循环依赖。
namespace WidgetTypes {

// 小组件静态元数据（来自 manifest.json）
struct WidgetInfo {
    QString id;
    QString name;
    QString icon;
    QString description;
    QString version;
    QString apiVersion;
    QString author;
    QString runtime;   // "qml"
    QString entry;     // 相对 widget 目录的入口，如 "main.qml"
    QSize defaultSize;            // 格数 {cols, rows}
    QList<QSize> supportedSizes;  // manifest 允许的占位尺寸（至少含 defaultSize）
    QVariantList settingsSchema;  // manifest 声明的配置项 schema（供配置面板渲染）
    bool builtin = false;
    QString dir;       // 绝对路径或 qrc 前缀（如 ":/widgets/clock"）

    bool isValid() const { return !id.isEmpty() && !entry.isEmpty(); }
};

// 已添加实例（installed.json 中的一条）
struct WidgetInstance {
    QString instanceId;
    QString widgetId;
    int gridX = -1;
    int gridY = -1;
    int cols = 2;
    int rows = 2;
};

} // namespace WidgetTypes
