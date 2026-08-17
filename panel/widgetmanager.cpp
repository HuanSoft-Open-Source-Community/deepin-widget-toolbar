// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetmanager.h"

#include "widgetgrid.h"
#include "widgetpackage.h"
#include "widgetschema.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonValue>
#include <QRect>
#include <QStandardPaths>
#include <QUuid>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>

// 网格列数统一取自 WidgetGrid::kColumns
static const char kManifestFile[] = "manifest.json";
static const char kInstancesFile[] = "installed.json";
static const char kWidgetsDirName[] = "widgets";
static const char kBuiltinPrefix[] = ":/widgets";

static bool writeJsonAtomically(const QString &path, const QJsonObject &object)
{
    const QFileInfo info(path);
    if (!info.dir().exists() && !QDir().mkpath(info.absolutePath()))
        return false;

    const QString tmpFile = path + QStringLiteral(".tmp");
    QFile f(tmpFile);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    f.close();

    if (QFile::exists(path) && !QFile::remove(path))
        return false;
    return QFile::rename(tmpFile, path);
}

WidgetManager::WidgetManager(QObject *parent)
    : QObject(parent)
{
}

void WidgetManager::init()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    m_dataDir = base + "/org.deepin.ds.widgettoolbar";
    m_widgetsDir = m_dataDir + "/" + kWidgetsDirName;
    m_instancesFile = m_dataDir + "/" + kInstancesFile;

    QDir().mkpath(m_widgetsDir);

    scanWidgets();
    loadInstances();
    // 一次性规范化旧数据：越界/重叠位置修复，不做持续补位
    normalizeLayout();
}

QList<WidgetManager::WidgetInfo> WidgetManager::availableWidgets() const
{
    return m_widgets;
}

QList<WidgetManager::Instance> WidgetManager::instances() const
{
    return m_instances;
}

QStringList WidgetManager::widgetIds() const
{
    QStringList ids;
    for (const WidgetInfo &w : m_widgets)
        ids << w.id;
    return ids;
}

QStringList WidgetManager::instanceIds() const
{
    QStringList ids;
    for (const Instance &inst : m_instances)
        ids << inst.instanceId;
    return ids;
}

QString WidgetManager::displayName(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->name : widgetId;
}

QString WidgetManager::iconName(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->icon : QString();
}

int WidgetManager::defaultCols(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->defaultSize.width() : 2;
}

int WidgetManager::defaultRows(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->defaultSize.height() : 2;
}

bool WidgetManager::isBuiltin(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->builtin : false;
}

bool WidgetManager::isInstalled(const QString &widgetId) const
{
    for (const Instance &inst : m_instances) {
        if (inst.widgetId == widgetId)
            return true;
    }
    return false;
}

QString WidgetManager::entryUrl(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    if (!w)
        return QString();

    if (w->builtin)
        return QLatin1String("qrc:/widgets/") + w->id + "/" + w->entry;
    return QUrl::fromLocalFile(w->dir + "/" + w->entry).toString();
}

QString WidgetManager::instanceWidgetId(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    return inst ? inst->widgetId : QString();
}

int WidgetManager::instanceCols(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    return inst ? inst->cols : 2;
}

int WidgetManager::instanceRows(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    return inst ? inst->rows : 2;
}

int WidgetManager::instanceGridX(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    return inst ? inst->gridX : -1;
}

int WidgetManager::instanceGridY(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    return inst ? inst->gridY : -1;
}

bool WidgetManager::canDrop(const QString &instanceId, int gridX, int gridY) const
{
    const Instance *inst = findInstance(instanceId);
    if (!inst)
        return false;

    if (gridX < 0 || gridY < 0)
        return false;

    return gridX + qBound(1, inst->cols, WidgetGrid::kColumns) <= WidgetGrid::kColumns;
}

bool WidgetManager::moveInstance(const QString &instanceId, int gridX, int gridY)
{
    Instance *inst = findInstance(instanceId);
    if (!inst || !canDrop(instanceId, gridX, gridY))
        return false;

    const QList<Instance> backup = m_instances;
    // 双向联动避让：计算避让布局后把拖拽实例落位到目标格
    QList<Instance> newLayout = WidgetGrid::computeAvoidance(m_instances, instanceId, gridX, gridY);
    for (Instance &entry : newLayout) {
        if (entry.instanceId == instanceId) {
            entry.gridX = gridX;
            entry.gridY = gridY;
            break;
        }
    }
    m_instances = newLayout;
    if (!saveInstances()) {
        m_instances = backup;
        qWarning() << "moveInstance: failed to save, rolled back";
        return false;
    }

    Q_EMIT layoutChanged();
    return true;
}

QVariantList WidgetManager::previewMove(const QString &instanceId, int gridX, int gridY)
{
    if (!canDrop(instanceId, gridX, gridY))
        return QVariantList();

    // 纯计算：不改动 m_instances，返回避让后的完整布局供 QML 实时预览
    const QList<Instance> layout = WidgetGrid::computeAvoidance(m_instances, instanceId, gridX, gridY);
    QVariantList result;
    result.reserve(layout.size());
    for (const Instance &inst : layout) {
        result.append(QVariantMap{
            {"instanceId", inst.instanceId},
            {"gridX", inst.gridX},
            {"gridY", inst.gridY},
        });
    }
    return result;
}

void WidgetManager::autoArrangeAll()
{
    const QList<Instance> backup = m_instances;

    // 按当前视觉顺序（先 y 后 x）压实，而不是按实例清单顺序：
    // 用户已手动摆整齐时，不会因为清单顺序与视觉顺序不一致而被无谓重排。
    QList<Instance> ordered = m_instances;
    std::stable_sort(ordered.begin(), ordered.end(), [](const Instance &a, const Instance &b) {
        if (a.gridY != b.gridY)
            return a.gridY < b.gridY;
        return a.gridX < b.gridX;
    });

    QList<Instance> placed;
    QList<Instance> packed = m_instances;
    for (const Instance &inst : ordered) {
        Instance copy = inst;
        WidgetGrid::placeFirstFree(copy, placed);
        placed.append(copy);
        for (Instance &target : packed) {
            if (target.instanceId == copy.instanceId) {
                target.gridX = copy.gridX;
                target.gridY = copy.gridY;
                break;
            }
        }
    }

    // 已经按同样规则压实：不重写文件、不发布局信号，避免“明明整齐还重排”。
    if (WidgetGrid::layoutEquals(m_instances, packed))
        return;

    m_instances = packed;
    if (!saveInstances()) {
        m_instances = backup;
        qWarning() << "autoArrangeAll: failed to save, rolled back";
        return;
    }

    Q_EMIT layoutChanged();
}

QVariantList WidgetManager::supportedSizes(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    if (!w)
        return QVariantList();

    QVariantList result;
    result.reserve(w->supportedSizes.size());
    for (const QSize &size : w->supportedSizes) {
        result.append(QVariantMap{
            {QStringLiteral("cols"), size.width()},
            {QStringLiteral("rows"), size.height()},
        });
    }
    return result;
}

bool WidgetManager::isSizeSupported(const QString &widgetId, int cols, int rows) const
{
    const WidgetInfo *w = findWidget(widgetId);
    if (!w)
        return false;
    return w->supportedSizes.contains(QSize(qBound(1, cols, WidgetGrid::kColumns), qMax(1, rows)));
}

bool WidgetManager::setInstanceSize(const QString &instanceId, int cols, int rows)
{
    Instance *inst = findInstance(instanceId);
    if (!inst || !findWidget(inst->widgetId))
        return false;
    if (!isSizeSupported(inst->widgetId, cols, rows))
        return false;

    cols = qBound(1, cols, WidgetGrid::kColumns);
    rows = qMax(1, rows);
    if (inst->cols == cols && inst->rows == rows)
        return true;

    const QList<Instance> backup = m_instances;
    QList<Instance> newLayout = m_instances;
    int targetX = inst->gridX < 0 ? 0 : qMin(inst->gridX, WidgetGrid::kColumns - cols);
    int targetY = qMax(0, inst->gridY);

    for (Instance &entry : newLayout) {
        if (entry.instanceId == instanceId) {
            entry.cols = cols;
            entry.rows = rows;
            break;
        }
    }

    // 以新的目标矩形做双向联动避让，保证扩大尺寸时不与其它实例重叠。
    newLayout = WidgetGrid::computeAvoidance(newLayout, instanceId, targetX, targetY);
    for (Instance &entry : newLayout) {
        if (entry.instanceId == instanceId) {
            entry.gridX = targetX;
            entry.gridY = targetY;
            break;
        }
    }

    m_instances = newLayout;
    if (!saveInstances()) {
        m_instances = backup;
        qWarning() << "setInstanceSize: failed to save, rolled back";
        return false;
    }

    Q_EMIT instancesChanged();
    return true;
}

QVariantList WidgetManager::widgetSettingsSchema(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->settingsSchema : QVariantList();
}

QString WidgetManager::instanceConfigPath(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    if (!inst)
        return QString();
    return widgetDataDir(inst->widgetId) + QLatin1Char('/') + instanceId + QStringLiteral(".config.json");
}

QVariantMap WidgetManager::instanceConfig(const QString &instanceId) const
{
    const Instance *inst = findInstance(instanceId);
    if (!inst)
        return QVariantMap();
    const WidgetInfo *w = findWidget(inst->widgetId);
    if (!w)
        return QVariantMap();

    QVariantMap config = WidgetSchema::defaultConfig(w->settingsSchema);
    const QStringList allowedKeys = WidgetSchema::schemaKeys(w->settingsSchema);
    const QString path = instanceConfigPath(instanceId);
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return config;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return config;
    const QJsonObject stored = doc.object();
    for (auto it = stored.constBegin(); it != stored.constEnd(); ++it) {
        if (allowedKeys.contains(it.key()))
            config.insert(it.key(), it.value().toVariant());
    }
    return config;
}

bool WidgetManager::saveInstanceConfig(const QString &instanceId, const QVariantMap &values)
{
    const Instance *inst = findInstance(instanceId);
    if (!inst)
        return false;
    const WidgetInfo *w = findWidget(inst->widgetId);
    if (!w)
        return false;

    const QStringList allowedKeys = WidgetSchema::schemaKeys(w->settingsSchema);
    QVariantMap config = instanceConfig(instanceId);
    for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
        if (allowedKeys.contains(it.key()))
            config.insert(it.key(), it.value());
    }

    QJsonObject object;
    for (auto it = config.constBegin(); it != config.constEnd(); ++it)
        object.insert(it.key(), QJsonValue::fromVariant(it.value()));

    const QString path = instanceConfigPath(instanceId);
    if (!writeJsonAtomically(path, object)) {
        qWarning() << "saveInstanceConfig: failed to save" << path;
        return false;
    }

    Q_EMIT instanceConfigChanged(instanceId);
    return true;
}

QStringList WidgetManager::usedZones(const QString &excludingInstanceId) const
{
    QStringList zones;
    for (const Instance &inst : m_instances) {
        if (inst.instanceId == excludingInstanceId)
            continue;

        // 仅统计声明了 dials 配置的组件（当前为世界时间）
        const QVariantList schema = widgetSettingsSchema(inst.widgetId);
        bool hasDials = false;
        for (const QVariant &entry : schema) {
            if (entry.toMap().value(QStringLiteral("key")).toString()
                == QLatin1String("dials")) {
                hasDials = true;
                break;
            }
        }
        if (!hasDials)
            continue;

        const QVariantList dials =
            instanceConfig(inst.instanceId).value(QStringLiteral("dials")).toList();
        for (const QVariant &dial : dials) {
            const QString zone = dial.toMap().value(QStringLiteral("zone")).toString();
            if (!zone.isEmpty() && !zones.contains(zone))
                zones.append(zone);
        }
    }
    return zones;
}

bool WidgetManager::addWidget(const QString &widgetId)
{
    if (findWidget(widgetId) == nullptr) {
        qWarning() << "addWidget: unknown widget" << widgetId;
        return false;
    }
    if (isInstalled(widgetId)) {
        qWarning() << "addWidget: already installed" << widgetId;
        return false;
    }

    const WidgetInfo *w = findWidget(widgetId);
    Instance inst;
    inst.instanceId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    inst.widgetId = widgetId;
    inst.cols = w->defaultSize.width();
    inst.rows = w->defaultSize.height();

    // 放入首个空闲格，不移动现有实例
    WidgetGrid::placeFirstFree(inst, m_instances);
    m_instances.append(inst);
    if (!saveInstances()) {
        m_instances.removeLast();
        return false;
    }

    // 预创建实例数据目录（FileIO 沙箱内）
    QDir().mkpath(widgetDataDir(widgetId));

    Q_EMIT instancesChanged();
    return true;
}

bool WidgetManager::removeInstance(const QString &instanceId)
{
    for (int i = 0; i < m_instances.size(); ++i) {
        if (m_instances.at(i).instanceId == instanceId) {
            const Instance removed = m_instances.at(i);
            m_instances.removeAt(i);
            if (!saveInstances()) {
                // 保存失败：回滚内存状态
                m_instances.insert(i, removed);
                qWarning() << "removeInstance: failed to save, rolled back";
                return false;
            }
            Q_EMIT instancesChanged();
            return true;
        }
    }
    qWarning() << "removeInstance: unknown instance" << instanceId;
    return false;
}

bool WidgetManager::uninstallWidget(const QString &widgetId)
{
    const WidgetInfo *w = findWidget(widgetId);
    if (!w)
        return false;
    if (w->builtin) {
        qWarning() << "uninstallWidget: builtin widget cannot be uninstalled" << widgetId;
        return false;
    }

    // 先移除该小组件的所有实例并保存；失败则回滚
    const QList<Instance> backup = m_instances;
    bool removed = false;
    for (int i = m_instances.size() - 1; i >= 0; --i) {
        if (m_instances.at(i).widgetId == widgetId) {
            m_instances.removeAt(i);
            removed = true;
        }
    }
    if (!saveInstances()) {
        m_instances = backup;
        qWarning() << "uninstallWidget: failed to save instances, rolled back";
        return false;
    }

    // 删除小组件目录；失败则恢复实例清单
    if (!WidgetPackage::removeWidgetDir(w->dir)) {
        m_instances = backup;
        saveInstances();
        return false;
    }

    scanWidgets();
    Q_EMIT widgetsChanged();
    if (removed)
        Q_EMIT instancesChanged();
    return true;
}

bool WidgetManager::installFromFile(const QString &packagePath)
{
    const WidgetPackage::InstallResult result = WidgetPackage::install(
        packagePath, m_widgetsDir,
        [this](const QString &widgetId) { return findWidget(widgetId) != nullptr; });
    if (!result.ok)
        return false;

    scanWidgets();
    Q_EMIT widgetsChanged();
    return true;
}

QString WidgetManager::widgetDataDir(const QString &widgetId) const
{
    return m_widgetsDir + "/" + widgetId + "/data";
}

QString WidgetManager::widgetsDataRoot() const
{
    return m_widgetsDir;
}

QString WidgetManager::widgetDir(const QString &widgetId) const
{
    const WidgetInfo *w = findWidget(widgetId);
    return w ? w->dir : QString();
}

void WidgetManager::scanWidgets()
{
    m_widgets.clear();

    // 内置：qrc:/widgets/<id>/
    const QDir builtinRoot{QLatin1String(kBuiltinPrefix)};
    if (builtinRoot.exists()) {
        const QStringList builtinIds = builtinRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &id : builtinIds) {
            const WidgetInfo info = readManifest(QLatin1String(kBuiltinPrefix) + "/" + id, true);
            if (info.isValid())
                m_widgets.append(info);
        }
    }

    // 第三方：~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/
    const QDir thirdRoot(m_widgetsDir);
    if (thirdRoot.exists()) {
        const QStringList thirdIds = thirdRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &id : thirdIds) {
            const WidgetInfo info = readManifest(m_widgetsDir + "/" + id, false);
            if (info.isValid())
                m_widgets.append(info);
        }
    }

    std::sort(m_widgets.begin(), m_widgets.end(), [](const WidgetInfo &a, const WidgetInfo &b) {
        if (a.builtin != b.builtin)
            return a.builtin;   // 内置在前
        return a.name < b.name;
    });
}

WidgetManager::WidgetInfo WidgetManager::readManifest(const QString &dir, bool builtin) const
{
    WidgetInfo info;
    QFile f(dir + "/" + kManifestFile);
    if (!f.open(QIODevice::ReadOnly))
        return info;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return info;
    const QJsonObject obj = doc.object();

    info.id = obj.value("id").toString();
    info.name = obj.value("name").toString();
    info.icon = obj.value("icon").toString();
    info.description = obj.value("description").toString();
    info.version = obj.value("version").toString();
    info.apiVersion = obj.value("apiVersion").toString();
    info.author = obj.value("author").toString();
    info.runtime = obj.value("runtime").toString("qml");
    info.entry = obj.value("entry").toString();
    info.builtin = builtin;
    info.dir = dir;

    // 校验：apiVersion 兼容（当前宿主仅支持 1.x）
    if (!info.apiVersion.startsWith("1.")) {
        qWarning() << "readManifest: unsupported apiVersion" << info.apiVersion << "for" << info.id;
        return WidgetInfo();
    }
    // 校验：entry 不能是绝对路径或含 .. 逃逸
    if (info.entry.isEmpty() || info.entry.startsWith('/') || info.entry.contains("..")) {
        qWarning() << "readManifest: unsafe entry" << info.entry << "for" << info.id;
        return WidgetInfo();
    }
    // 校验：entry 文件存在
    if (!QFile::exists(dir + "/" + info.entry)) {
        qWarning() << "readManifest: entry not found" << dir << info.entry;
        return WidgetInfo();
    }

    const QJsonObject sizeObj = obj.value("defaultSize").toObject();
    // 钳制尺寸范围：cols ∈ [1,4]，rows ≥ 1
    info.defaultSize = QSize(qBound(1, sizeObj.value("cols").toInt(2), WidgetGrid::kColumns),
                             qMax(1, sizeObj.value("rows").toInt(2)));

    // 可选尺寸列表：旧 manifest 未声明时只允许默认尺寸。
    const QJsonArray sizes = obj.value("sizes").toArray();
    for (const QJsonValue &value : sizes) {
        if (!value.isObject())
            continue;
        const QJsonObject entry = value.toObject();
        const int cols = entry.value("cols").toInt(0);
        const int rows = entry.value("rows").toInt(0);
        if (cols < 1 || cols > WidgetGrid::kColumns || rows < 1)
            continue;
        const QSize candidate(cols, rows);
        if (!info.supportedSizes.contains(candidate)) {
            info.supportedSizes.append(candidate);
        }
    }
    if (!info.supportedSizes.contains(info.defaultSize))
        info.supportedSizes.prepend(info.defaultSize);

    info.settingsSchema = WidgetSchema::parseSettingsSchema(obj.value("settings").toArray());

    // 多语言名称：name[zh_CN] 等
    const QString lk = WidgetSchema::localeKey("name");
    if (obj.contains(lk))
        info.name = obj.value(lk).toString();

    if (info.name.isEmpty())
        info.name = info.id;

    return info;
}

bool WidgetManager::loadInstances()
{
    m_instances.clear();
    QFile f(m_instancesFile);
    if (!f.exists())
        return true;   // 首次运行，无清单
    if (!f.open(QIODevice::ReadOnly))
        return false;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    const QJsonArray arr = doc.object().value("instances").toArray();
    for (const QJsonValue &v : arr) {
        if (v.isObject()) {
            const Instance inst = instanceFromJson(v.toObject());
            if (!inst.instanceId.isEmpty() && findWidget(inst.widgetId))
                m_instances.append(inst);
        }
    }
    return true;
}

bool WidgetManager::saveInstances() const
{
    QJsonArray arr;
    for (const Instance &inst : m_instances)
        arr.append(instanceToJson(inst));

    QJsonObject root;
    root.insert("version", 1);
    root.insert("instances", arr);

    // 原子写：先写临时文件再 rename，避免崩溃损坏清单
    const QString tmpFile = m_instancesFile + ".tmp";
    QFile f(tmpFile);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.close();

    if (QFile::exists(m_instancesFile) && !QFile::remove(m_instancesFile))
        return false;
    return QFile::rename(tmpFile, m_instancesFile);
}

void WidgetManager::normalizeLayout()
{
    const QList<Instance> before = m_instances;

    // 一次性数据修复：越界/负坐标实例重新放入首个空闲格（不移动其它实例）
    QList<Instance> fixed;
    for (const Instance &inst : m_instances) {
        Instance copy = inst;
        // 兼容旧清单或 manifest 变更：不支持的尺寸回退到组件默认尺寸。
        if (const WidgetInfo *w = findWidget(copy.widgetId)) {
            if (!w->supportedSizes.contains(QSize(qBound(1, copy.cols, WidgetGrid::kColumns),
                                                 qMax(1, copy.rows)))) {
                copy.cols = w->defaultSize.width();
                copy.rows = w->defaultSize.height();
            }
        }
        const QRect rect = WidgetGrid::instanceRect(copy);
        if (copy.gridX < 0 || copy.gridY < 0
            || copy.gridX + rect.width() > WidgetGrid::kColumns) {
            WidgetGrid::placeFirstFree(copy, fixed);
        }
        fixed.append(copy);
    }
    m_instances = fixed;

    // 持久化数据中残留的重叠：按列表顺序固定靠前者，让其它实例双向避让
    const int maxPasses = m_instances.size() + 1;
    for (int pass = 0; pass < maxPasses; ++pass) {
        bool overlap = false;
        QString anchorId;
        int anchorX = 0;
        int anchorY = 0;
        for (int i = 0; i < m_instances.size() && !overlap; ++i) {
            const QRect a = WidgetGrid::instanceRect(m_instances.at(i));
            for (int j = i + 1; j < m_instances.size(); ++j) {
                if (a.intersects(WidgetGrid::instanceRect(m_instances.at(j)))) {
                    anchorId = m_instances.at(i).instanceId;
                    anchorX = m_instances.at(i).gridX;
                    anchorY = m_instances.at(i).gridY;
                    overlap = true;
                    break;
                }
            }
        }
        if (!overlap)
            break;
        m_instances = WidgetGrid::computeAvoidance(m_instances, anchorId, anchorX, anchorY);
    }

    if (!WidgetGrid::layoutEquals(before, m_instances))
        saveInstances();
}

WidgetManager::Instance WidgetManager::instanceFromJson(const QJsonObject &obj)
{
    Instance inst;
    inst.instanceId = obj.value("instanceId").toString();
    inst.widgetId = obj.value("widgetId").toString();
    inst.gridX = obj.value("gridX").toInt(-1);
    inst.gridY = obj.value("gridY").toInt(-1);
    inst.cols = obj.value("cols").toInt(2);
    inst.rows = obj.value("rows").toInt(2);
    return inst;
}

QJsonObject WidgetManager::instanceToJson(const Instance &inst)
{
    QJsonObject obj;
    obj.insert("instanceId", inst.instanceId);
    obj.insert("widgetId", inst.widgetId);
    obj.insert("gridX", inst.gridX);
    obj.insert("gridY", inst.gridY);
    obj.insert("cols", inst.cols);
    obj.insert("rows", inst.rows);
    return obj;
}

const WidgetManager::WidgetInfo *WidgetManager::findWidget(const QString &widgetId) const
{
    for (const WidgetInfo &w : m_widgets) {
        if (w.id == widgetId)
            return &w;
    }
    return nullptr;
}

WidgetManager::WidgetInfo *WidgetManager::findWidget(const QString &widgetId)
{
    for (WidgetInfo &w : m_widgets) {
        if (w.id == widgetId)
            return &w;
    }
    return nullptr;
}

const WidgetManager::Instance *WidgetManager::findInstance(const QString &instanceId) const
{
    for (const Instance &inst : m_instances) {
        if (inst.instanceId == instanceId)
            return &inst;
    }
    return nullptr;
}

WidgetManager::Instance *WidgetManager::findInstance(const QString &instanceId)
{
    for (Instance &inst : m_instances) {
        if (inst.instanceId == instanceId)
            return &inst;
    }
    return nullptr;
}
