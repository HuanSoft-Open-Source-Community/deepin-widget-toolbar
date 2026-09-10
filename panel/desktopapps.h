// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>

class QDBusServiceWatcher;
class QFileSystemWatcher;
class QTimer;
class QQuickImageProvider;

// 宿主能力代理（QML 单例 org.deepin.widgettoolbar/DesktopApps）：
// 为"应用快捷启动器"等小组件提供桌面程序条目（desktop entries）。
//
// 条目聚合与 dde-launchpad/dde-shell 一致：合并 XDG 启动器目录（用户/系统）、
// flatpak 与如意玲珑 entries（/var/lib、~/.local、~/.linglong）、
// deepin 应用商店 /opt/apps/<id>/entries/applications，按目录优先级去重，
// 过滤 Hidden/Type!=Application/OnlyShowIn 不含 X-Deepin 等不应显示的项；
// NoDisplay 条目保留为可解析/可启动并参与默认程序匹配，但不进 entries
// 应用列表（控制中心"默认程序"的自定义启动器即为此类）。输出本地化显示名
// 与主题图标名并稳定排序；宿主用 QFileSystemWatcher 监听各目录，
// 软件装/卸时自动刷新。
//
// 启动走 dde 生态应用管理器（会话总线 org.desktopspec.ApplicationManager1，
// dde-application-manager 提供，dock/启动器同源；由其负责 flatpak/linglong 的
// 容器化包装与运行环境）；该服务不在线或调用失败时降级为解析 Exec 直接启动。
//
// 同时提供默认程序解析（浏览器/终端/文本编辑器/邮箱：XDG mimeapps +
// com.deepin.desktop.default-applications.terminal，与控制中心同源）。
class DesktopApps : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged FINAL)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged FINAL)

public:
    explicit DesktopApps(QObject *parent = nullptr);
    ~DesktopApps() override;

    struct Entry {               // 内部条目（仅供本类实现使用）
        QString id;              // 规范化 desktop id（不带 .desktop）
        QString name;            // 本地化显示名
        QString icon;            // 主题图标名或绝对路径
        QString exec;            // Exec 原文（降级启动用）
        bool noDisplay = false;  // NoDisplay：可解析/可启动/参与默认程序匹配，
                                 // 但不进 entries 应用列表（控制中心"默认程序"
                                 // 的自定义启动器即为此类，见 rebuildEntries）
    };

    // 应用管理器（org.desktopspec.ApplicationManager1）是否在线（决定启动通道）
    bool available() const;
    // 全部可见应用 [{id, name, icon}]，按本地化名排序
    QVariantList entries() const;
    // 单条查询：本地化显示名 / 主题图标名（查不到返回空串）
    Q_INVOKABLE QString nameOf(const QString &desktopId) const;
    Q_INVOKABLE QString iconNameOf(const QString &desktopId) const;
    // 应用图标的 QML Image source（image://dwtappicon/...@像素）：
    // 空图标名回退通用可执行图标；渲染引擎与 dde-shell 图标主题一致
    Q_INVOKABLE QString iconSource(const QString &iconName, int px) const;
    // 启动一个应用（应用管理器负责 flatpak/linglong 等容器化包装）
    Q_INVOKABLE bool launch(const QString &desktopId);
    // 默认程序：[浏览器, 终端, 文本编辑器, 邮箱] 的 desktop id（解析不到为空串）
    Q_INVOKABLE QStringList defaultAppIds();
    // 强制重建（目录内容变化时宿主自动调度，一般无需手动触发）
    Q_INVOKABLE void refresh();

    // 供 WidgetToolbarPanel 注册 QQuickImageProvider 的工厂；
    // 请求 id 格式：<iconName|绝对路径>@<像素>（百分号编码）
    static QQuickImageProvider *createIconProvider();

Q_SIGNALS:
    void availableChanged(bool available);
    void entriesChanged();

private:
    void setAmAvailable(bool available);
    void setupDirectoryWatchers();
    void rescanDirectories();
    void rebuildEntries();
    Entry *findEntry(const QString &desktopId);
    bool launchViaManager(Entry *entry);
    bool launchExecFallback(QString exec, const QString &appName);
    QString defaultMimeHandler(const QStringList &mimeKeys) const;
    QString firstExistingId(const QStringList &candidates) const;
    QString defaultTerminalId() const;

    QHash<QString, Entry> m_apps;             // id -> Entry
    QVariantList m_entriesCache;
    bool m_amAvailable = false;
    QPointer<QDBusServiceWatcher> m_serviceWatcher;
    QFileSystemWatcher *m_fsWatcher = nullptr;
    QTimer *m_rescanTimer = nullptr;
};
