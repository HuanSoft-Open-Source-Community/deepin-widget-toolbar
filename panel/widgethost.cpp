// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgethost.h"

#include "widgetmanager.h"
#include "widgetschema.h"
#include "widgettoolbarpanel.h"
#include "windowguard.h"

#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QQuickWindow>
#include <QUrl>

WidgetHost::WidgetHost(WidgetManager *manager, QObject *parent)
    : QObject(parent)
    , m_manager(manager)
{
}

bool WidgetHost::saveConfig(const QString &instanceId, const QVariantMap &values)
{
    if (!m_manager)
        return false;

    // image 类型的值落盘前校验（空串 = 未设置；非空必须是相对 dataDir 的
    // 相对路径）：小组件自身也能经本入口回写配置，无效值（如 ".." 上跳）
    // 会让图片读取逃出实例目录。无效键剔除后保存其余键（配置面板每次全量
    // 保存，直接拒绝会导致该实例所有配置改不动）
    QVariantMap sanitized = values;
    const QString widgetId = m_manager->instanceWidgetId(instanceId);
    if (!widgetId.isEmpty()) {
        const QVariantList schema = m_manager->widgetSettingsSchema(widgetId);
        for (const QVariant &entryVar : schema) {
            const QVariantMap entry = entryVar.toMap();
            if (entry.value(QStringLiteral("type")).toString() != QLatin1String("image"))
                continue;
            const QString key = entry.value(QStringLiteral("key")).toString();
            if (!sanitized.contains(key))
                continue;
            const QString value = sanitized.value(key).toString();
            if (!WidgetSchema::isValidImageValue(value)) {
                qWarning() << "WidgetHost::saveConfig: reject invalid image value"
                           << "for key" << key << "of instance" << instanceId;
                sanitized.remove(key);
            }
        }
    }

    return m_manager->saveInstanceConfig(instanceId, sanitized);
}

QStringList WidgetHost::usedZones(const QString &excludingInstanceId)
{
    if (!m_manager)
        return QStringList();
    return m_manager->usedZones(excludingInstanceId);
}

void WidgetHost::activateWindow()
{
    // 契约：宿主单例必须以面板为 parent（widgettoolbarpanel.cpp 注册时如此传入），
    // 面板窗口由它取出交给 WindowGuard 直设 X 输入焦点。若将来改挂到别的 parent，
    // 这里会取不到面板——静默返回会让"便签点了却打不进字"变得无从下手，故告警。
    auto *panel = qobject_cast<WidgetToolbarPanel *>(parent());
    if (!panel) {
        qWarning() << "WidgetHost::activateWindow: parent is not WidgetToolbarPanel;"
                   << "keyboard focus request dropped (check the singleton registration)";
        return;
    }
    WindowGuard::ensureKeyboardFocus(panel->rootWindow());
}

void WidgetHost::requestOpenAppPicker(const QString &instanceId, int index)
{
    Q_EMIT openAppPickerRequested(instanceId, index);
}

// 实例数据目录（image 等实例文件统一放在 <dataDir>/<instanceId>/ 子目录）。
// instanceId 来自实例表（UUID），这里仍防御性拒绝含路径分隔符/".." 的值，
// 保证目标目录固定在实例子目录内
static QString instanceDataDir(WidgetManager *manager, const QString &instanceId)
{
    if (!manager || instanceId.isEmpty())
        return QString();
    if (instanceId.contains(QLatin1Char('/')) || instanceId.contains(QLatin1String("..")))
        return QString();
    const QString widgetId = manager->instanceWidgetId(instanceId);
    if (widgetId.isEmpty())
        return QString();
    const QString dataDir = manager->widgetDataDir(widgetId);
    return dataDir.isEmpty() ? QString() : dataDir;
}

QString WidgetHost::importInstanceImage(const QString &instanceId, const QString &sourceFilePath)
{
    const QString dataDir = instanceDataDir(m_manager, instanceId);
    if (dataDir.isEmpty())
        return QString();

    // 文件对话框可能回传 file:// URL，统一归一化为本地路径
    const QUrl sourceUrl(sourceFilePath);
    const QString source = sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : sourceFilePath;
    const QFileInfo sourceInfo(source);
    if (!sourceInfo.isFile())
        return QString();

    static const QStringList kImageSuffixes = {
        QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"),
        QStringLiteral("bmp"), QStringLiteral("webp")
    };
    const QString suffix = sourceInfo.suffix().toLower();
    if (!kImageSuffixes.contains(suffix))
        return QString();

    const QDir instanceDir(dataDir + QLatin1Char('/') + instanceId);
    if (!instanceDir.exists() && !QDir().mkpath(instanceDir.absolutePath()))
        return QString();

    // 目标名 img-<毫秒时间戳>.<后缀>，撞名时追加序号
    const QString base = QStringLiteral("img-")
        + QString::number(QDateTime::currentMSecsSinceEpoch());
    QString fileName = base + QLatin1Char('.') + suffix;
    for (int attempt = 1; QFile::exists(instanceDir.filePath(fileName)); ++attempt) {
        if (attempt >= 100)
            return QString();
        fileName = base + QLatin1Char('-') + QString::number(attempt)
            + QLatin1Char('.') + suffix;
    }

    const QString target = instanceDir.filePath(fileName);
    if (!QFile::copy(source, target)) {
        qWarning() << "WidgetHost::importInstanceImage: copy failed"
                   << source << "->" << target;
        return QString();
    }
    return instanceId + QLatin1Char('/') + fileName;
}

bool WidgetHost::removeInstanceImage(const QString &instanceId, const QString &relativePath)
{
    const QString dataDir = instanceDataDir(m_manager, instanceId);
    if (dataDir.isEmpty())
        return false;

    // 只允许删除实例子目录内的文件：拒绝绝对路径与 ".."，再做规范化与
    // 符号链接解析双重校验（防符号链接把删除目标指到实例目录外）
    if (relativePath.isEmpty() || relativePath.startsWith(QLatin1Char('/'))
        || relativePath.contains(QLatin1String("..")))
        return false;

    const QString instanceDirPath = QDir::cleanPath(dataDir + QLatin1Char('/') + instanceId);
    const QString instanceDirCanonical = QFileInfo(instanceDirPath).canonicalFilePath();
    if (instanceDirCanonical.isEmpty())
        return false;

    const QString absolute = QDir::cleanPath(instanceDirPath + QLatin1Char('/') + relativePath);
    if (!absolute.startsWith(instanceDirCanonical + QLatin1Char('/')))
        return false;

    const QString canonicalFile = QFileInfo(absolute).canonicalFilePath();
    if (canonicalFile.isEmpty()
        || !canonicalFile.startsWith(instanceDirCanonical + QLatin1Char('/')))
        return false;

    return QFile::remove(absolute);
}
