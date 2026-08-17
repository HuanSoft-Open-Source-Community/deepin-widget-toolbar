// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "widgettypes.h"

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QRect>
#include <QSize>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>

// 小组件宿主（Panel）侧的管理器（编排层）：
//  - 扫描内置（qrc:/widgets/）与第三方（~/.local/share/org.deepin.ds.widgettoolbar/widgets/）小组件
//  - 解析 manifest.json，维护已添加实例清单 installed.json
//  - 4 列网格空闲槽分配与双向避让（算法在 WidgetGrid）
//  - .dwpkg（tar.xz）导入与第三方卸载（文件操作在 WidgetPackage）
// 基础类型（WidgetInfo/WidgetInstance）定义在 WidgetTypes。
class WidgetManager : public QObject
{
    Q_OBJECT
public:
    // 兼容别名：外部代码仍可用 WidgetManager::WidgetInfo / WidgetManager::Instance
    using WidgetInfo = WidgetTypes::WidgetInfo;
    using Instance = WidgetTypes::WidgetInstance;

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
    // 拖放目标是否可用：仅校验网格边界（占用格允许落位，冲突由避让解决）
    Q_INVOKABLE bool canDrop(const QString &instanceId, int gridX, int gridY) const;
    // 拖拽中实时预览：计算并返回避让后的完整布局（不修改持久状态）；越界返回空列表
    Q_INVOKABLE QVariantList previewMove(const QString &instanceId, int gridX, int gridY);
    // 拖放落位：成功则触发沿列下推避让并持久化
    Q_INVOKABLE bool moveInstance(const QString &instanceId, int gridX, int gridY);
    // 自动整理：按当前视觉顺序左上优先压实；已整齐时跳过，避免无谓重排
    Q_INVOKABLE void autoArrangeAll();
    // 组件允许的尺寸预设（QVariantList of {"cols":n,"rows":m}）
    Q_INVOKABLE QVariantList supportedSizes(const QString &widgetId) const;
    Q_INVOKABLE bool isSizeSupported(const QString &widgetId, int cols, int rows) const;
    // 修改实例占位尺寸：保持左上角偏好位置，冲突时联动避让并持久化
    Q_INVOKABLE bool setInstanceSize(const QString &instanceId, int cols, int rows);
    // 实例配置面板：schema + 当前值 + 保存（按实例持久化）
    Q_INVOKABLE QVariantList widgetSettingsSchema(const QString &widgetId) const;
    Q_INVOKABLE QVariantMap instanceConfig(const QString &instanceId) const;
    Q_INVOKABLE bool saveInstanceConfig(const QString &instanceId, const QVariantMap &values);
    // 收集其它实例 dials 配置中已使用的时区 id（世界时间跨实例地区唯一性用）
    Q_INVOKABLE QStringList usedZones(const QString &excludingInstanceId) const;

    // 添加一个小组件实例（放入首个空闲格，不移动其它实例）
    Q_INVOKABLE bool addWidget(const QString &widgetId);
    // 移除一个实例（其余实例保持原位，留洞）
    Q_INVOKABLE bool removeInstance(const QString &instanceId);
    // 卸载第三方小组件（删除其目录；内置拒绝），其余实例保持原位
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
    // 实例集合变化（添加/移除/卸载）：QML 需重建模型
    void instancesChanged();
    // 仅位置变化（拖放落位/一键整理）：QML 只更新位置映射以保留动画
    void layoutChanged();
    // 某个实例的配置已保存（QML 需刷新注入的 widgetConfig）
    void instanceConfigChanged(const QString &instanceId);

private:
    void scanWidgets();
    WidgetInfo readManifest(const QString &dir, bool builtin) const;
    bool loadInstances();
    bool saveInstances() const;
    // 加载后一次性规范化（越界/重叠修复），仅在布局变化时写回；
    // 空闲槽搜索与双向避让算法在 WidgetGrid
    void normalizeLayout();
    const WidgetInfo *findWidget(const QString &widgetId) const;
    WidgetInfo *findWidget(const QString &widgetId);
    const Instance *findInstance(const QString &instanceId) const;
    Instance *findInstance(const QString &instanceId);
    QString instanceConfigPath(const QString &instanceId) const;
    static Instance instanceFromJson(const QJsonObject &obj);
    static QJsonObject instanceToJson(const Instance &inst);

    QString m_dataDir;      // ~/.local/share/org.deepin.ds.widgettoolbar
    QString m_widgetsDir;   // m_dataDir/widgets（第三方安装目录）
    QString m_instancesFile;
    QList<WidgetInfo> m_widgets;
    QList<Instance> m_instances;
};
