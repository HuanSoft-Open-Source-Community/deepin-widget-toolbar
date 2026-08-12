// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>

// 宿主提供给小组件的文件访问代理（QML 单例 org.deepin.widgettoolbar/FileIO）：
// 沙箱约束——只允许访问 allowedRoot（小组件数据目录）内的路径，
// 其余路径一律拒绝，防止第三方小组件读写任意用户文件。
class FileIO : public QObject
{
    Q_OBJECT
public:
    explicit FileIO(QObject *parent = nullptr);

    // 设置允许访问的根目录（canonical），由宿主在初始化时注入
    void setAllowedRoot(const QString &path);

    Q_INVOKABLE QString readTextFile(const QString &path) const;
    Q_INVOKABLE bool writeTextFile(const QString &path, const QString &content) const;
    Q_INVOKABLE bool exists(const QString &path) const;

private:
    bool isAllowed(const QString &path) const;

    QString m_allowedRoot;
};
