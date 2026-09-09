// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "desktopapps.h"

#include <QCollator>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QIcon>
#include <QLocale>
#include <QPainter>
#include <QProcess>
#include <QQuickImageProvider>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <utility>

// ===== 常量 =====

// dde 应用管理器（dde-application-manager）：启动应用的首选通道（负责
// linglong/flatpak 容器化包装）；条目聚合本身走目录扫描（与 dde-launchpad 一致）。
static const char kAmService[] = "org.desktopspec.ApplicationManager1";
static const char kAmPath[] = "/org/desktopspec/ApplicationManager1";
static const char kAppInterface[] = "org.desktopspec.ApplicationManager1.Application";

// 条目目录（优先级从高到低）：XDG 标准（用户在前）再补 flatpak/linglong exports。
// 与 dde-launchpad/dde-shell 的应用来源一致：系统 XDG 目录、~/.local、flatpak
// exports（系统 + 用户）、如意玲珑 entries（系统 + 无根用户目录）。
static QStringList fallbackApplicationsDirs()
{
    QStringList dirs = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    const QStringList extras = {
        QStringLiteral("/var/lib/flatpak/exports/share/applications"),
        QStringLiteral("/var/lib/linglong/entries/apps/share/applications"),
        QStringLiteral("/var/lib/linglong/entries/share/applications"),
        QStringLiteral("/var/lib/linglong/entries/applications"),
    };
    for (const QString &extra : extras) {
        if (QDir(extra).exists() && !dirs.contains(extra))
            dirs.append(extra);
    }
    const QString home = QDir::homePath();
    const QStringList homeExtras = {
        home + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
        home + QStringLiteral("/.linglong/entries/apps/share/applications"),
    };
    for (const QString &extra : homeExtras) {
        if (QDir(extra).exists() && !dirs.contains(extra))
            dirs.append(extra);
    }
    return dirs;
}

// 规范化 desktop id（不带 .desktop 后缀）。该结果同时用于：条目库键（m_apps）、
// 实例配置落盘（launchers）、mimeapps 默认程序匹配、AM 启动对象路径编码，
// 四处必须一致，因此这里按 ".desktop" 的真实长度 8 精确截尾（曾误截 9 个
// 字符，导致所有带后缀 id 丢失末字符的回归）。
static QString normalizeDesktopId(QString id)
{
    id = id.trimmed();
    // 容忍带路径或 .desktop 后缀的写法
    const int slash = id.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0)
        id = id.mid(slash + 1);
    if (id.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive))
        id.chop(8);
    return id;
}

// ===== 桌面条目文件解析 =====

namespace {

struct RawDesktopFile {
    QString name;          // 本地化 Name
    QString icon;          // Icon
    QString exec;          // Exec
    QString type;          // Type
    bool noDisplay = false;
    bool hidden = false;
    QStringList onlyShowIn;
    QStringList notShowIn;
};

QString unescapeDesktopValue(QString value)
{
    // .desktop 转义：\s \n \t \r \\（\; 在拆列表时处理）
    value.replace(QStringLiteral("\\s"), QStringLiteral(" "));
    value.replace(QStringLiteral("\\n"), QStringLiteral("\n"));
    value.replace(QStringLiteral("\\t"), QStringLiteral("\t"));
    value.replace(QStringLiteral("\\r"), QStringLiteral("\r"));
    value.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
    return value;
}

QStringList splitDesktopList(QString value)
{
    QStringList result;
    // 保护 \; 转义，再按 ; 拆分
    value.replace(QStringLiteral("\\;"), QStringLiteral("\x01"));
    const QStringList parts = value.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (QString part : parts)
        result.append(part.replace(QLatin1Char('\x01'), QStringLiteral(";")));
    return result;
}

QStringList localeCandidates()
{
    QStringList list;
    const QString locale = QLocale::system().name();   // zh_CN
    if (!locale.isEmpty())
        list.append(locale);
    const int underscore = locale.indexOf(QLatin1Char('_'));
    if (underscore > 0)
        list.append(locale.left(underscore));
    list.append(QStringLiteral("en_US"));
    return list;
}

RawDesktopFile parseDesktopFile(const QString &path)
{
    RawDesktopFile out;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return out;

    const QByteArray data = f.readAll();
    QString section;
    const QList<QByteArray> lines = data.split('\n');
    const QStringList localeHits = localeCandidates();

    QHash<QString, QString> localizedName;
    QString plainName;

    for (const QByteArray &raw : lines) {
        QString line = QString::fromUtf8(raw).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            section = line.mid(1, line.length() - 2).trimmed();
            continue;
        }
        if (section != QLatin1String("Desktop Entry"))
            continue;
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        const QString key = line.left(eq).trimmed();
        const QString value = unescapeDesktopValue(line.mid(eq + 1).trimmed());

        if (key == QLatin1String("Name")) {
            plainName = value;
        } else if (key.startsWith(QLatin1String("Name["))) {
            const QString tag = key.mid(5, key.length() - 6);   // Name[zh_CN] -> zh_CN
            localizedName.insert(tag, value);
        } else if (key == QLatin1String("Icon")) {
            out.icon = value;
        } else if (key == QLatin1String("Exec")) {
            out.exec = value;
        } else if (key == QLatin1String("Type")) {
            out.type = value;
        } else if (key == QLatin1String("NoDisplay")) {
            out.noDisplay = value == QLatin1String("true") || value == QLatin1String("1")
                || value == QLatin1String("yes");
        } else if (key == QLatin1String("Hidden")) {
            out.hidden = value == QLatin1String("true") || value == QLatin1String("1")
                || value == QLatin1String("yes");
        } else if (key == QLatin1String("OnlyShowIn")) {
            out.onlyShowIn = splitDesktopList(value);
        } else if (key == QLatin1String("NotShowIn")) {
            out.notShowIn = splitDesktopList(value);
        }
    }

    for (const QString &candidate : localeHits) {
        const auto it = localizedName.constFind(candidate);
        if (it != localizedName.constEnd()) {
            out.name = it.value();
            return out;
        }
    }
    out.name = plainName;
    return out;
}

} // namespace

// ===== 图标查找域扩展 =====

// dde 生态的应用图标可能只存在于应用自带图标树（如如意玲珑
// /opt/apps/<id>/entries/icons/...），标准图标主题目录不含这些路径，
// 导致 dde 启动器有图标而我们的 fromTheme 落空。这里把已存在的候选根
// 追加进 Qt 图标主题搜索路径（进程内一次性、幂等），并重设主题触发重扫。
static void setupIconSearchPaths()
{
    QStringList paths = QIcon::themeSearchPaths();
    QStringList extraRoots = {
        QStringLiteral("/var/lib/flatpak/exports/share/icons"),
        QStringLiteral("/var/lib/linglong/entries/share/icons"),
        QStringLiteral("/var/lib/linglong/entries/apps/share/icons"),
        QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/icons"),
    };
    // 应用自带图标树：/opt/apps/*/entries/icons（含 hicolor/index.theme）
    const QDir appsRoot(QStringLiteral("/opt/apps"));
    if (appsRoot.exists()) {
        const QStringList appIds = appsRoot.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &appId : appIds)
            extraRoots.append(appsRoot.filePath(appId) + QStringLiteral("/entries/icons"));
    }
    bool changed = false;
    for (const QString &root : std::as_const(extraRoots)) {
        if (QDir(root).exists() && !paths.contains(root)) {
            paths.append(root);
            changed = true;
        }
    }
    if (changed) {
        QIcon::setThemeSearchPaths(paths);
        // 触发主题缓存重建
        QIcon::setThemeName(QIcon::themeName());
    }
}

// ===== 应用图标渲染 provider =====

// 与 dde-shell 相同的方式显示应用图标：把 desktop 条目里的图标名交给 Qt 图标主题
// 解析（v25 的 bloom 主题含 .dci，由 dde-qt6integration 的 icon engine 支持），
// 渲染成像素图后供 QML Image 直接加载。
// 请求 id 格式：<iconName|绝对路径>@<像素>（像素部分未经百分号编码，先按最后的
// '@' 拆分，再对名称段解码）。
class DesktopAppIconProvider : public QQuickImageProvider
{
public:
    DesktopAppIconProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        QString raw = id;
        int px = 64;
        const int at = raw.lastIndexOf(QLatin1Char('@'));
        if (at > 0) {
            bool ok = false;
            const int parsed = raw.mid(at + 1).toInt(&ok);
            if (ok && parsed > 0) {
                px = parsed;
                raw = raw.left(at);
            }
        }
        px = qBound(16, px, 1024);
        if (size)
            *size = QSize(px, px);

        const QString name = QString::fromUtf8(
            QByteArray::fromPercentEncoding(raw.toUtf8()));

        QIcon icon;
        bool wasNamedIcon = false;
        QString lookupName = name;
        if (name.isEmpty()) {
            icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        } else if (name.startsWith(QLatin1Char('/')) || name.startsWith(QLatin1String("file:"))) {
            const QString path = name.startsWith(QLatin1String("file:")) ? name.mid(5) : name;
            icon = QIcon(path);
            if (icon.isNull() || icon.pixmap(px, px).isNull()) {
                // 绝对路径不可用（容器内私有/已卸载残留）：回退 basename 走主题名
                lookupName = QFileInfo(path).fileName();
                icon = QIcon();
                wasNamedIcon = true;
            }
        } else {
            wasNamedIcon = true;
        }
        if (wasNamedIcon) {
            icon = QIcon::fromTheme(lookupName);
            if (icon.isNull()) {
                // 去 -symbolic 等常见变体再试一次
                QString stripped = lookupName;
                if (stripped.endsWith(QLatin1String("-symbolic")))
                    stripped.chop(9);
                if (stripped != lookupName)
                    icon = QIcon::fromTheme(stripped);
            }
            if (icon.isNull())
                icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        }

        QPixmap pixmap;
        if (!icon.isNull())
            pixmap = icon.pixmap(QSize(px, px));
        if (pixmap.isNull()) {
            // 记录缺图（每名字一次），便于按日志清单补查找域
            static QSet<QString> sLoggedMisses;
            if (!lookupName.isEmpty() && !sLoggedMisses.contains(lookupName)) {
                sLoggedMisses.insert(lookupName);
                qWarning() << "DesktopApps: icon miss" << lookupName;
            }
            // 占位：透明底 + 灰圆角方块 + 简化应用图样
            pixmap = QPixmap(px, px);
            pixmap.fill(Qt::transparent);
            QPainter painter(&pixmap);
            painter.setRenderHint(QPainter::Antialiasing);
            const qreal radius = px * 0.18;
            painter.setPen(Qt::NoPen);
            painter.setBrush(QColor(120, 120, 120, 70));
            painter.drawRoundedRect(QRectF(1, 1, px - 2, px - 2), radius, radius);
            painter.setBrush(QColor(255, 255, 255, 150));
            const qreal cx = px / 2.0;
            painter.drawEllipse(QPointF(cx, px * 0.36), px * 0.18, px * 0.18);
            painter.drawRoundedRect(
                QRectF(px * 0.27, px * 0.58, px * 0.46, px * 0.24), px * 0.08, px * 0.08);
        }
        return pixmap;
    }
};

// ===== DesktopApps 宿主代理 =====

DesktopApps::DesktopApps(QObject *parent)
    : QObject(parent)
{
    setupIconSearchPaths();

    // 启动通道可用性探测
    const auto *iface = QDBusConnection::sessionBus().interface();
    m_amAvailable = iface
        && iface->isServiceRegistered(QString::fromLatin1(kAmService));

    m_serviceWatcher = new QDBusServiceWatcher(
        QString::fromLatin1(kAmService), QDBusConnection::sessionBus(),
        QDBusServiceWatcher::WatchForRegistration
            | QDBusServiceWatcher::WatchForUnregistration, this);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, [this]() { setAmAvailable(true); });
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, [this]() { setAmAvailable(false); });

    // 目录内容变化（软件装/卸、应用自更新）合并重扫
    m_rescanTimer = new QTimer(this);
    m_rescanTimer->setSingleShot(true);
    m_rescanTimer->setInterval(400);
    connect(m_rescanTimer, &QTimer::timeout, this, &DesktopApps::rescanDirectories);

    m_fsWatcher = new QFileSystemWatcher(this);
    connect(m_fsWatcher, &QFileSystemWatcher::directoryChanged,
            this, [this]() {
                if (!m_rescanTimer->isActive())
                    m_rescanTimer->start();
            });

    const QStringList dirs = fallbackApplicationsDirs();
    QStringList existing;
    for (const QString &dir : dirs) {
        if (QDir(dir).exists())
            existing.append(dir);
    }
    if (!existing.isEmpty())
        m_fsWatcher->addPaths(existing);

    rescanDirectories();
}

DesktopApps::~DesktopApps() = default;

bool DesktopApps::available() const
{
    return m_amAvailable;
}

void DesktopApps::setAmAvailable(bool available)
{
    if (m_amAvailable == available)
        return;
    m_amAvailable = available;
    Q_EMIT availableChanged(available);
}

QVariantList DesktopApps::entries() const
{
    return m_entriesCache;
}

QString DesktopApps::nameOf(const QString &desktopId) const
{
    const QString id = normalizeDesktopId(desktopId);
    const auto it = m_apps.constFind(id);
    if (it == m_apps.constEnd())
        return QString();
    return it->name.isEmpty() ? id : it->name;
}

QString DesktopApps::iconNameOf(const QString &desktopId) const
{
    const QString id = normalizeDesktopId(desktopId);
    const auto it = m_apps.constFind(id);
    return it == m_apps.constEnd() ? QString() : it->icon;
}

QString DesktopApps::iconSource(const QString &iconName, int px) const
{
    QString name = iconName.trimmed();
    if (name.isEmpty())
        name = QStringLiteral("application-x-executable");
    const int pixel = qBound(16, px <= 0 ? 64 : px, 1024);
    const QString encoded = QString::fromUtf8(QUrl::toPercentEncoding(name));
    return QStringLiteral("image://dwtappicon/%1@%2").arg(encoded).arg(pixel);
}

DesktopApps::Entry *DesktopApps::findEntry(const QString &desktopId)
{
    const QString id = normalizeDesktopId(desktopId);
    if (id.isEmpty())
        return nullptr;
    auto it = m_apps.find(id);
    return it == m_apps.end() ? nullptr : &it.value();
}

// 重扫全部条目目录（与 dde-shell 应用列表同一批目录、同一套过滤规则）
void DesktopApps::rescanDirectories()
{
    const QStringList dirs = fallbackApplicationsDirs();
    QHash<QString, Entry> next;
    next.reserve(m_apps.size() + 64);

    for (const QString &dir : dirs) {
        const QDir d(dir);
        if (!d.exists())
            continue;
        const QFileInfoList files = d.entryInfoList({ QStringLiteral("*.desktop") },
                                                    QDir::Files | QDir::Readable);
        for (const QFileInfo &file : files) {
            const QString id = normalizeDesktopId(file.fileName());
            if (id.isEmpty() || next.contains(id))
                continue;
            const RawDesktopFile raw = parseDesktopFile(file.absoluteFilePath());
            if (raw.noDisplay || raw.hidden)
                continue;
            if (!raw.type.isEmpty() && raw.type != QLatin1String("Application"))
                continue;
            // OnlyShowIn/NotShowIn：只对 deepin 系桌面可见的应用开放
            if (!raw.onlyShowIn.isEmpty()
                && !raw.onlyShowIn.contains(QStringLiteral("X-Deepin"))
                && !raw.onlyShowIn.contains(QStringLiteral("X-Unified")))
                continue;
            if (raw.notShowIn.contains(QStringLiteral("X-Deepin"))
                || raw.notShowIn.contains(QStringLiteral("X-Unified")))
                continue;
            if (raw.name.isEmpty())
                continue;

            Entry entry;
            entry.id = id;
            entry.name = raw.name;
            entry.icon = raw.icon;
            entry.exec = raw.exec;
            next.insert(id, entry);
        }
    }

    // 比对后仅在有变化时重建输出（避免无谓刷小组件）
    bool changed = next.size() != m_apps.size();
    if (!changed) {
        for (auto it = next.cbegin(); it != next.cend(); ++it) {
            const auto old = m_apps.constFind(it.key());
            if (old == m_apps.constEnd()
                || old->name != it->name || old->icon != it->icon
                || old->exec != it->exec) {
                changed = true;
                break;
            }
        }
    }
    if (!changed)
        return;
    m_apps = next;
    qWarning() << "DesktopApps: registry size" << m_apps.size()
               << "dirs" << dirs.size();
    rebuildEntries();
}

void DesktopApps::refresh()
{
    rescanDirectories();
}

void DesktopApps::rebuildEntries()
{
    QCollator collator(QLocale::system());
    collator.setCaseSensitivity(Qt::CaseInsensitive);

    QStringList ids;
    ids.reserve(m_apps.size());
    for (auto it = m_apps.cbegin(); it != m_apps.cend(); ++it)
        ids.append(it.key());
    std::sort(ids.begin(), ids.end(), [&](const QString &a, const QString &b) {
        const QString na = m_apps.value(a).name;
        const QString nb = m_apps.value(b).name;
        const int cmp = collator.compare(na, nb);
        if (cmp != 0)
            return cmp < 0;
        return a < b;
    });

    QVariantList list;
    list.reserve(ids.size());
    for (const QString &id : std::as_const(ids)) {
        const Entry &entry = m_apps.value(id);
        QVariantMap item;
        item.insert(QStringLiteral("id"), entry.id);
        item.insert(QStringLiteral("name"), entry.name.isEmpty() ? entry.id : entry.name);
        item.insert(QStringLiteral("icon"), entry.icon);
        list.append(item);
    }
    m_entriesCache = list;
    Q_EMIT entriesChanged();
}

// ===== 启动 =====

// AM 对象路径 = 根路径 + "/" + id（id 中除 [A-Za-z0-9] 外按 "_" + 两位十六进制编码，
// 与 dde-application-manager 的路径编码一致：'-' -> _2d、'.' -> _2e、'_' -> _5f）
static QString amObjectPathForId(const QString &id)
{
    QString escaped;
    escaped.reserve(id.size() + 8);
    for (const QChar ch : id) {
        const ushort u = ch.unicode();
        if ((u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z')
            || (u >= '0' && u <= '9')) {
            escaped.append(ch);
        } else {
            escaped.append(QLatin1Char('_'));
            escaped.append(QString::number(u, 16).rightJustified(2, QLatin1Char('0')));
        }
    }
    return QString::fromLatin1(kAmPath) + QLatin1Char('/') + escaped;
}

bool DesktopApps::launch(const QString &desktopId)
{
    Entry *entry = findEntry(desktopId);
    if (!entry)
        return false;

    // 优先经应用管理器（容器化应用需要 AM 处理 flatpak/linglong 环境与运行参数）
    if (m_amAvailable) {
        // 回调内按值快照，避免重扫替换 m_apps 后指针失效
        const QString launchId = entry->id;
        const QString launchExec = entry->exec;
        const QString launchName = entry->name;
        QDBusMessage call = QDBusMessage::createMethodCall(
            QString::fromLatin1(kAmService), amObjectPathForId(launchId),
            QString::fromLatin1(kAppInterface), QStringLiteral("Launch"));
        call << QString() << QStringList() << QVariantMap();
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(call), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, launchId, launchExec, launchName](QDBusPendingCallWatcher *w) {
                    if (w->isError()) {
                        qWarning() << "DesktopApps: AM launch failed for" << launchId
                                   << ":" << w->error().message()
                                   << "- falling back to direct Exec";
                        // AM 缺对象/忙时回退直接执行（flatpak/linglong 的
                        // Exec 已含 run 包装命令，可独立运行）
                        launchExecFallback(launchExec, launchName);
                    }
                    w->deleteLater();
                });
        return true;
    }

    // AM 不在线：直接执行解析后的 Exec
    if (entry->exec.isEmpty())
        return false;
    return launchExecFallback(entry->exec, entry->name);
}

bool DesktopApps::launchExecFallback(QString exec, const QString &appName)
{
    // 轻量 tokenize：支持单双引号与反斜杠转义；不支持 shell 变量/管道（desktop Exec 规范内）
    QStringList args;
    QString token;
    QChar quote = QLatin1Char('\0');
    bool escaped = false;
    for (const QChar ch : exec) {
        if (escaped) {
            token.append(ch);
            escaped = false;
            continue;
        }
        if (ch == QLatin1Char('\\')) {
            escaped = true;
            continue;
        }
        if (quote.isNull()) {
            if (ch == QLatin1Char('\'') || ch == QLatin1Char('"')) {
                quote = ch;
            } else if (ch.isSpace()) {
                if (!token.isEmpty()) {
                    args.append(token);
                    token.clear();
                }
            } else {
                token.append(ch);
            }
        } else if (ch == quote) {
            quote = QLatin1Char('\0');
        } else {
            token.append(ch);
        }
    }
    if (!token.isEmpty())
        args.append(token);

    if (args.isEmpty())
        return false;
    const QString program = args.takeFirst();

    // 展开字段码：无文件参数场景下 %f/%F/%u/%U 等一律为空，%% 转义为 %，
    // %c 为应用名；%i/%k 无对应数据时同样展开为空（规范允许）
    static const QString removableCodes = QStringLiteral("fFuUdDnNvmik");
    QStringList expanded;
    expanded.reserve(args.size());
    for (const QString &arg : args) {
        QString out;
        out.reserve(arg.size());
        for (int i = 0; i < arg.size(); ++i) {
            const QChar ch = arg.at(i);
            if (ch == QLatin1Char('%') && i + 1 < arg.size()) {
                const QChar next = arg.at(i + 1);
                if (next == QLatin1Char('%')) {
                    out.append(QLatin1Char('%'));
                    i += 1;
                    continue;
                }
                if (next == QLatin1Char('c')) {
                    out.append(appName);
                    i += 1;
                    continue;
                }
                if (removableCodes.contains(next)) {
                    i += 1;
                    continue;
                }
            }
            out.append(ch);
        }
        if (!out.isEmpty())
            expanded.append(out);
    }
    return QProcess::startDetached(program, expanded);
}

// ===== 默认程序解析 =====

static QStringList mimeappsFiles()
{
    QStringList files;
    const QString configHome = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    if (!configHome.isEmpty())
        files.append(configHome + QStringLiteral("/mimeapps.list"));
    const QStringList configDirs = QStandardPaths::standardLocations(QStandardPaths::ConfigLocation);
    for (const QString &dir : configDirs) {
        if (dir != configHome)
            files.append(dir + QStringLiteral("/mimeapps.list"));
    }
    const QStringList dataDirs =
        QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &dir : dataDirs)
        files.append(dir + QStringLiteral("/mimeapps.list"));
    return files;
}

QString DesktopApps::defaultMimeHandler(const QStringList &mimeKeys) const
{
    // [Default Applications] 优先，再兜底 [Added Associations]
    for (const QString &section : { QStringLiteral("Default Applications"),
                                    QStringLiteral("Added Associations") }) {
        for (const QString &filePath : mimeappsFiles()) {
            if (!QFile::exists(filePath))
                continue;
            QSettings settings(filePath, QSettings::IniFormat);
            for (const QString &key : mimeKeys) {
                const QString value =
                    settings.value(section + QLatin1Char('/') + key).toString();
                for (const QString &candidate :
                     value.split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
                    const QString normalized = normalizeDesktopId(candidate);
                    if (m_apps.contains(normalized))
                        return normalized;
                }
            }
        }
    }
    return QString();
}

QString DesktopApps::firstExistingId(const QStringList &candidates) const
{
    for (const QString &candidate : candidates) {
        const QString normalized = normalizeDesktopId(candidate);
        if (m_apps.contains(normalized))
            return normalized;
    }
    return QString();
}

QString DesktopApps::defaultTerminalId() const
{
    // 控制中心"默认程序"里终端设置的落点（com.deepin.desktop.default-applications.terminal）
    QProcess process;
    process.start(QStringLiteral("gsettings"), {
        QStringLiteral("get"),
        QStringLiteral("com.deepin.desktop.default-applications.terminal"),
        QStringLiteral("app-id") });
    if (process.waitForFinished(800)) {
        const QString output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        if (output.size() >= 2 && output.startsWith(QLatin1Char('\''))
            && output.endsWith(QLatin1Char('\''))) {
            const QString id = normalizeDesktopId(output.mid(1, output.size() - 2));
            if (m_apps.contains(id))
                return id;
        }
    }
    return firstExistingId({
        QStringLiteral("deepin-terminal"), QStringLiteral("x-terminal-emulator"),
        QStringLiteral("konsole"), QStringLiteral("gnome-terminal"),
        QStringLiteral("xfce4-terminal") });
}

QStringList DesktopApps::defaultAppIds()
{
    QStringList result;
    qWarning() << "DesktopApps: defaultAppIds begin, registry size" << m_apps.size();
    result.append(defaultMimeHandler({
        QStringLiteral("x-scheme-handler/http"),
        QStringLiteral("x-scheme-handler/https") }));
    if (result.last().isEmpty())
        result.last() = firstExistingId({
            QStringLiteral("org.deepin.browser"), QStringLiteral("firefox-esr"),
            QStringLiteral("firefox"), QStringLiteral("org.mozilla.firefox"),
            QStringLiteral("google-chrome"), QStringLiteral("chromium") });

    result.append(defaultTerminalId());

    result.append(defaultMimeHandler({
        QStringLiteral("text/plain"), QStringLiteral("text/markdown") }));
    if (result.last().isEmpty())
        result.last() = firstExistingId({
            QStringLiteral("deepin-editor"), QStringLiteral("gedit"),
            QStringLiteral("kate"), QStringLiteral("pluma"), QStringLiteral("mousepad") });

    result.append(defaultMimeHandler({ QStringLiteral("x-scheme-handler/mailto") }));
    if (result.last().isEmpty())
        result.last() = firstExistingId({
            QStringLiteral("deepin-mail"), QStringLiteral("thunderbird"),
            QStringLiteral("org.mozilla.Thunderbird"), QStringLiteral("org.gnome.Evolution") });
    qWarning() << "DesktopApps: defaultAppIds =>" << result;
    return result;
}

QQuickImageProvider *DesktopApps::createIconProvider()
{
    return new DesktopAppIconProvider();
}
