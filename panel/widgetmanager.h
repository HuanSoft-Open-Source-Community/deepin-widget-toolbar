// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QSize>
#include <QStringList>

// 小组件宿主（Panel）侧的管理器：
//  - 扫描内置（qrc:/widgets/）与第三方（~/.local/share/org.deepin.ds.widgettoolbar/widgets/）小组件
//  - 解析 manifest.json，维护已添加实例清单 installed.json
//  - 4 列网格空闲槽分配
//  - .dwpkg（tar.xz）导入与第三方卸载（内置禁止卸载）
class WidgetManager : public QObject
{
    Q_OBJECT
public:
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
        QSize defaultSize; // 格数 {cols, rows}
        bool builtin = false;
        QString dir;       // 绝对路径或 qrc 前缀（如 ":/widgets/clock"）

        bool isValid() const { return !id.isEmpty() && !entry.isEmpty(); }
    };

    // 已添加实例（installed.json 中的一条）
    struct Instance {
        QString instanceId;
        QString widgetId;
        int gridX = -1;
        int gridY = -1;
        int cols = 2;
        int rows = 2;
    };

    explicit WidgetManager(QObject *parent = nullptr);

    // 初始化：扫描小组件、加载实例清单
    void init();

    // 内置 + 已安装第三方 的可添加列表
    QList<WidgetInfo> availableWidgets() const;
    QList<Instance> instances() const;

    // 供 QML 使用
    Q_INVOKABLE QStringList widgetIds() const;
    Q_INVOKABLE QStringList instanceIds() const;
    Q_INVOKABLE QString displayName(const QString &widgetId) const;
    Q_INVOKABLE QString iconName(const QString &widgetId) const;
    Q_INVOKABLE int defaultCols(const QString &widgetId) const;
    Q_INVOKABLE int defaultRows(const QString &widgetId) const;
    Q_INVOKABLE bool isBuiltin(const QString &widgetId) const;
    Q_INVOKABLE bool isInstalled(const QString &widgetId) const;
    // 小组件渲染入口的 URL（qrc:/widgets/... 或 file:///...），供 QML Loader 加载
    Q_INVOKABLE QString entryUrl(const QString &widgetId) const;
    // 实例元数据（供 QML 网格布局使用）
    Q_INVOKABLE QString instanceWidgetId(const QString &instanceId) const;
    Q_INVOKABLE int instanceCols(const QString &instanceId) const;
    Q_INVOKABLE int instanceRows(const QString &instanceId) const;
    Q_INVOKABLE int instanceGridX(const QString &instanceId) const;
    Q_INVOKABLE int instanceGridY(const QString &instanceId) const;

    // 添加一个小组件实例（自动分配网格槽）
    Q_INVOKABLE bool addWidget(const QString &widgetId);
    // 移除一个实例
    Q_INVOKABLE bool removeInstance(const QString &instanceId);
    // 卸载第三方小组件（删除其目录；内置拒绝）
    Q_INVOKABLE bool uninstallWidget(const QString &widgetId);
    // 从 .dwpkg（tar.xz）导入第三方小组件
    Q_INVOKABLE bool installFromFile(const QString &packagePath);

    // 第三方小组件数据目录（实例数据隔离用）：~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/data
    Q_INVOKABLE QString widgetDataDir(const QString &widgetId) const;
    // 小组件安装目录
    Q_INVOKABLE QString widgetDir(const QString &widgetId) const;
    // 小组件数据根目录（FileIO 沙箱允许根）
    Q_INVOKABLE QString widgetsDataRoot() const;

Q_SIGNALS:
    void widgetsChanged();
    void instancesChanged();

private:
    void scanWidgets();
    WidgetInfo readManifest(const QString &dir, bool builtin) const;
    bool loadInstances();
    bool saveInstances() const;
    bool assignGridSlot(Instance &inst) const;
    const WidgetInfo *findWidget(const QString &widgetId) const;
    WidgetInfo *findWidget(const QString &widgetId);
    const Instance *findInstance(const QString &instanceId) const;
    Instance *findInstance(const QString &instanceId);
    static Instance instanceFromJson(const QJsonObject &obj);
    static QJsonObject instanceToJson(const Instance &inst);

    QString m_dataDir;      // ~/.local/share/org.deepin.ds.widgettoolbar
    QString m_widgetsDir;   // m_dataDir/widgets（第三方安装目录）
    QString m_instancesFile;
    QList<WidgetInfo> m_widgets;
    QList<Instance> m_instances;
};
