// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetmanager.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QLocale>
#include <QProcess>
#include <QRect>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUuid>
#include <QUrl>

#include <algorithm>

static constexpr int kGridColumns = 4;
static const char kManifestFile[] = "manifest.json";
static const char kInstancesFile[] = "installed.json";
static const char kWidgetsDirName[] = "widgets";
static const char kBuiltinPrefix[] = ":/widgets";

static QString localeKey(const QString &base)
{
    // manifest 多语言字段：name[zh_CN] 形式
    const QString locale = QLocale::system().name();   // 如 zh_CN / en_US
    if (!locale.isEmpty())
        return base + "[" + locale + "]";
    return base;
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

    if (!assignGridSlot(inst)) {
        qWarning() << "addWidget: no free grid slot for" << widgetId;
        return false;
    }

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
    QDir dir(w->dir);
    if (!dir.removeRecursively()) {
        m_instances = backup;
        saveInstances();
        qWarning() << "uninstallWidget: failed to remove dir" << w->dir;
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
    const QFileInfo pkg(packagePath);
    if (!pkg.exists() || !pkg.isFile()) {
        qWarning() << "installFromFile: invalid package path" << packagePath;
        return false;
    }

    QTemporaryDir tmp;
    if (!tmp.isValid()) {
        qWarning() << "installFromFile: cannot create temp dir";
        return false;
    }

    // 1. 列出包内容，拒绝路径穿越（.. 或绝对路径）
    QProcess listProc;
    listProc.start("tar", {"-tJf", packagePath});
    if (!listProc.waitForFinished(15000) || listProc.exitCode() != 0) {
        qWarning() << "installFromFile: tar list failed" << listProc.readAllStandardError();
        return false;
    }
    const QStringList entries = QString::fromUtf8(listProc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const QString &e : entries) {
        if (e.startsWith('/') || e.contains("..")) {
            qWarning() << "installFromFile: unsafe path in package:" << e;
            return false;
        }
    }

    // 2. 解压到临时目录
    QProcess extractProc;
    extractProc.start("tar", {"-xJf", packagePath, "-C", tmp.path()});
    if (!extractProc.waitForFinished(30000) || extractProc.exitCode() != 0) {
        qWarning() << "installFromFile: tar extract failed" << extractProc.readAllStandardError();
        return false;
    }

    // 2.5 解压后校验：所有条目 canonical 路径必须位于临时目录内
    //（防包内 symlink/hardlink 前缀逃逸，如 CVE-2016-6321 一类）
    {
        const QString tmpCanonical = QDir(tmp.path()).canonicalPath();
        QDirIterator it(tmp.path(), QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString canonical = QFileInfo(it.next()).canonicalFilePath();
            if (canonical.isEmpty() || (!canonical.startsWith(tmpCanonical + "/") && canonical != tmpCanonical)) {
                qWarning() << "installFromFile: entry escapes temp dir:" << canonical;
                return false;
            }
        }
    }

    // 3. 在解压结果中查找 manifest.json（包根或第一层子目录）
    QString manifestPath;
    const QString rootManifest = tmp.path() + "/" + kManifestFile;
    if (QFile::exists(rootManifest)) {
        manifestPath = rootManifest;
    } else {
        const QDir root(tmp.path());
        const QStringList subDirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &sub : subDirs) {
            const QString candidate = tmp.path() + "/" + sub + "/" + kManifestFile;
            if (QFile::exists(candidate)) {
                manifestPath = candidate;
                break;
            }
        }
    }
    if (manifestPath.isEmpty()) {
        qWarning() << "installFromFile: manifest.json not found in package";
        return false;
    }

    // 4. 校验 manifest 中的 id 合法性
    QFile mf(manifestPath);
    if (!mf.open(QIODevice::ReadOnly)) {
        qWarning() << "installFromFile: cannot read manifest";
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(mf.readAll());
    const QJsonObject obj = doc.object();
    const QString widgetId = obj.value("id").toString();
    static const QRegularExpression idRe(QStringLiteral("^[A-Za-z0-9._-]+$"));
    if (!idRe.match(widgetId).hasMatch()) {
        qWarning() << "installFromFile: invalid widget id in manifest:" << widgetId;
        return false;
    }
    if (findWidget(widgetId)) {
        qWarning() << "installFromFile: widget already exists:" << widgetId;
        return false;
    }

    // 5. 移动到安装目录
    const QFileInfo mfInfo(manifestPath);
    const QString sourceDir = mfInfo.absolutePath();
    const QString targetDir = m_widgetsDir + "/" + widgetId;
    QDir().mkpath(m_widgetsDir);
    QDir src(sourceDir);
    if (!src.rename(sourceDir, targetDir)) {
        qWarning() << "installFromFile: move to" << targetDir << "failed";
        return false;
    }

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
    info.defaultSize = QSize(qBound(1, sizeObj.value("cols").toInt(2), kGridColumns),
                             qMax(1, sizeObj.value("rows").toInt(2)));

    // 多语言名称：name[zh_CN] 等
    const QString lk = localeKey("name");
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

bool WidgetManager::assignGridSlot(Instance &inst) const
{
    // 钳制尺寸边界：cols ∈ [1,4]，rows ≥ 1
    inst.cols = qBound(1, inst.cols, kGridColumns);
    inst.rows = qMax(1, inst.rows);

    // 逐行扫描 4 列网格，寻找能容纳 (cols, rows) 的空闲矩形
    const int maxY = 256;
    for (int y = 0; y < maxY; ++y) {
        for (int x = 0; x <= kGridColumns - inst.cols; ++x) {
            bool free = true;
            for (const Instance &other : m_instances) {
                const QRect otherRect(other.gridX, other.gridY, other.cols, other.rows);
                const QRect candidate(x, y, inst.cols, inst.rows);
                if (otherRect.intersects(candidate)) {
                    free = false;
                    break;
                }
            }
            if (free) {
                inst.gridX = x;
                inst.gridY = y;
                return true;
            }
        }
    }
    return false;
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
