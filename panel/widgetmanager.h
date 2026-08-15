// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QRect>
#include <QSize>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>

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
        QSize defaultSize;            // 格数 {cols, rows}
        QList<QSize> supportedSizes;  // manifest 允许的占位尺寸（至少含 defaultSize）
        QVariantList settingsSchema;  // manifest 声明的配置项 schema（供配置面板渲染）
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
    // 把 inst 放入首个空闲矩形（不移动其它实例），放不下时追加到最底行下方
    void placeFirstFree(Instance &inst, const QList<Instance> &others) const;
    // 双向联动避让：返回避让后的实例列表；fixedId 实例保持原位置（预览用），
    // 其它实例保持 gridX，只调 gridY，向最近空闲行移动（中心在上→优先向上，否则向下）
    static QList<Instance> computeAvoidance(const QList<Instance> &instances,
                                            const QString &fixedId,
                                            int targetX, int targetY);
    // 加载后一次性规范化（越界/重叠修复），仅在布局变化时写回
    void normalizeLayout();
    static QRect instanceRect(const Instance &inst);
    static bool layoutEquals(const QList<Instance> &a, const QList<Instance> &b);
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
