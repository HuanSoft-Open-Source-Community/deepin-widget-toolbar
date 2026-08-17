// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>

#include <functional>

// 第三方小组件包（.dwpkg，tar.xz）的校验与安装/卸载。
// 仅做文件层操作：实例清单维护、重扫与信号由调用方（WidgetManager）负责。
class WidgetPackage
{
public:
    struct InstallResult {
        bool ok = false;
        QString widgetId;   // 成功安装的小组件 id（失败时为空）
    };

    // 校验并安装 .dwpkg 到 destWidgetsDir/<id>/：
    // 路径穿越（.. / 绝对路径 / symlink 逃逸）与 id 合法性校验，
    // existsCheck 用于拒绝已存在的小组件 id。
    static InstallResult install(
        const QString &packagePath,
        const QString &destWidgetsDir,
        const std::function<bool(const QString &widgetId)> &existsCheck);

    // 删除小组件安装目录（卸载的文件层操作）
    static bool removeWidgetDir(const QString &widgetDir);
};
