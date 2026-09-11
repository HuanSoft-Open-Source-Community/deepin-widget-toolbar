// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "debuglogger.h"

#include <QDebug>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>

// 文件名 = 日期 + "_" + 时间 + ".log"。日期与时间必须各自用自己的 toString：
// 把 "yyyyMMdd_HHmmss" 整串丢给 QDate::toString 会让 H/m/s 按**字面量**输出
// （QDate 不认识时分秒记号），得到 "20260911_HHmmss" 这种坏名字。
static const char kDateFormat[] = "yyyyMMdd";
static const char kTimeFormat[] = "HHmmss";

DebugLogger::DebugLogger(QObject *parent)
    : QObject(parent)
    , m_logDir(logDirectoryPath())
{
    // 目录建失败不致命：只是没有日志，绝不能让面板因此起不来
    if (!m_logDir.exists() && !m_logDir.mkpath(QStringLiteral(".")))
        qWarning().noquote() << "[WidgetToolbar] cannot create log dir" << m_logDir.absolutePath();
}

DebugLogger::~DebugLogger()
{
    QMutexLocker locker(&m_mutex);
    if (m_logFile.isOpen()) {
        m_logFile.flush();
        m_logFile.close();
    }
}

DebugLogger *DebugLogger::instance()
{
    static DebugLogger singleton;
    return &singleton;
}

QString DebugLogger::logDirectoryPath()
{
    // 走 XDG cache（deepl 与 dde-shell 均为普通用户运行，写 /var/log 需要 root，
    // 且缓存目录随用户清理策略自然回收）：~/.cache/logs/deepin-widget-toolbar
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    return cache + "/logs/deepin-widget-toolbar";
}

bool DebugLogger::isEnabled() const
{
    QMutexLocker locker(&m_mutex);
    return m_enabled;
}

qint64 DebugLogger::totalLinesWritten() const
{
    return m_totalLines;
}

int DebugLogger::currentFileLines() const
{
    QMutexLocker locker(&m_mutex);
    return m_lineCount;
}

void DebugLogger::setEnabled(bool enabled)
{
    QMutexLocker locker(&m_mutex);
    if (m_enabled == enabled) {
        // 幂等：重复设同值不重开文件，避免每次 DConfig 通知都追加一段会话头
        return;
    }
    m_enabled = enabled;
    if (enabled) {
        ensureLogFile();
    } else if (m_logFile.isOpen()) {
        m_logFile.flush();
        m_logFile.close();
    }
}

QString DebugLogger::currentLogPath() const
{
    QMutexLocker locker(&m_mutex);
    return m_currentFileName.isEmpty() ? QString() : m_logDir.filePath(m_currentFileName);
}

void DebugLogger::flushAndRotate()
{
    QMutexLocker locker(&m_mutex);
    if (!m_logFile.isOpen())
        return;
    m_logFile.flush();
    checkRotation(true);
}

void DebugLogger::log(Level level, const QString &component, const QString &message)
{
    // 注意：DEBUG_* 宏已在外部判过 isEnabled 以免构造字符串；这里再判一次，
    // 覆盖直接调用 log() 的路径（如 DEBUG_WARNING 不经宏门控）。
    QMutexLocker locker(&m_mutex);
    if (!m_enabled)
        return;

    ensureLogFile();
    if (!m_logFile.isOpen())
        return; // 目录/磁盘不可用：静默放弃，不影响业务

    writeToFile(formatLine(QDateTime::currentDateTime(), level, component, message));
    ++m_lineCount;
    ++m_totalLines;
    checkRotation(false);
}

void DebugLogger::logThrottled(const QString &key, int intervalMs, Level level,
                               const QString &component, const QString &message)
{
    QMutexLocker locker(&m_mutex);
    if (!m_enabled)
        return;

    const QDateTime now = QDateTime::currentDateTime();
    const auto last = m_lastWritten.constFind(key);
    if (last != m_lastWritten.constEnd() && last->msecsTo(now) < intervalMs) {
        // 抑制而非丢弃：攒下的条数在下次真正写入时补报，避免"看起来没发生"
        m_suppressed[key] = m_suppressed.value(key) + 1;
        return;
    }

    QString out = message;
    const qint64 dropped = m_suppressed.take(key);
    if (dropped > 0)
        out += QStringLiteral(" [+%1 suppressed in last %2ms]").arg(dropped).arg(intervalMs);

    m_lastWritten[key] = now;

    ensureLogFile();
    if (!m_logFile.isOpen())
        return;
    writeToFile(formatLine(now, level, component, out));
    ++m_lineCount;
    ++m_totalLines;
    checkRotation(false);
}

QString DebugLogger::nextTimestampedName() const
{
    // 同一秒内多次轮转（狂刷日志时可能）会撞名，逐个加 _N 后缀另起
    const QString base = QStringLiteral("%1_%2.log")
                             .arg(QDate::currentDate().toString(QLatin1String(kDateFormat)),
                                  QTime::currentTime().toString(QLatin1String(kTimeFormat)));
    if (!QFileInfo::exists(m_logDir.filePath(base)))
        return base;
    for (int n = 2; n <= 9999; ++n) {
        const QString candidate = base.left(base.size() - 4) + QStringLiteral("_%1.log").arg(n);
        if (!QFileInfo::exists(m_logDir.filePath(candidate)))
            return candidate;
    }
    // 撞名兜底：退回带毫秒，绝不覆盖已有文件
    return QStringLiteral("%1_%2.log")
        .arg(QDate::currentDate().toString(QLatin1String(kDateFormat)),
             QTime::currentTime().toString(QStringLiteral("HHmmsszzz")));
}

int DebugLogger::countLinesIn(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    // 分块数换行符，避免为统计行数把整个文件读进内存；本类的写入每行都以
    // '\n' 结尾，故换行符计数即行数，无需为"末行无换行"再补一。
    int lines = 0;
    constexpr qint64 blockSize = 64 * 1024;
    while (!f.atEnd())
        lines += f.read(blockSize).count('\n');
    return lines;
}

void DebugLogger::ensureLogFile()
{
    const bool haveName = !m_currentFileName.isEmpty();
    // 额外要求"文件在磁盘上仍然存在"：~/.cache 是用户随手就清的地方（清理工具、
    // 磁盘紧张、logrotate 都会动它），而面板是长驻进程。若文件已被删掉却仍按
    // 旧句柄往下写，日志会进到一个不存在的 inode 里悄悄丢光，且随后的轮转
    // rename 必然失败。发现路径消失就重新挑一个文件名，自愈继续记。
    const bool sameAlive = haveName && m_logFile.isOpen()
        && m_logFile.fileName() == m_logDir.filePath(m_currentFileName)
        && QFileInfo::exists(m_logFile.fileName());
    if (sameAlive) {
        return; // 已在写当前文件
    }
    if (haveName && !QFileInfo::exists(m_logDir.filePath(m_currentFileName)))
        m_currentFileName.clear(); // 文件已被外部删除：作废旧名，另起新篇

    if (m_currentFileName.isEmpty())
        m_currentFileName = nextTimestampedName();

    const QString fullPath = m_logDir.filePath(m_currentFileName);
    if (m_logFile.isOpen())
        m_logFile.close();

    if (!m_logDir.exists() && !m_logDir.mkpath(QStringLiteral("."))) {
        qWarning().noquote() << "[WidgetToolbar] cannot create log dir" << m_logDir.absolutePath();
        return;
    }

    // 关键：文件是否本来就有内容，决定行计数从 0 起还是从既有行数起。
    // 否则每次进程重启都把 m_lineCount 归零，而文件是 Append 打开的，
    // 单个日志文件就能一路超过 2500 行 —— 上限直接被击穿。
    const bool preexisting = QFileInfo::exists(fullPath);
    m_lineCount = preexisting ? countLinesIn(fullPath) : 0;

    m_logFile.setFileName(fullPath);
    if (!m_logFile.open(QIODevice::Append | QIODevice::Text)) {
        qWarning().noquote() << "[WidgetToolbar] cannot open log file" << fullPath
                             << m_logFile.errorString();
        m_currentFileName.clear(); // 让下次调用重新挑一个名字
        return;
    }

    if (!preexisting) {
        QTextStream out(&m_logFile);
        out << QStringLiteral("========== deepin-widget-toolbar debug log started "
                              "%1 (line limit %2 per file) ==========\n")
                   .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")),
                        QString::number(kMaxLinesPerFile));
        ++m_lineCount;
        ++m_totalLines;
    }
}

void DebugLogger::checkRotation(bool force)
{
    if (!m_logFile.isOpen())
        return;
    if (!force && m_lineCount < kMaxLinesPerFile)
        return;

    m_logFile.flush();
    m_logFile.close();

    // 旧文件存档名：<时间戳>.<序号>.log —— 序号只拼在去掉 .log 的主干上，
    // 免得产出 "20250911_155530.log_rotated.1.log" 那种双扩展名怪名
    const QString stem = m_currentFileName.left(m_currentFileName.size() - 4); // 去掉 .log
    QString archived;
    bool renamed = false;
    for (int seq = 1; seq <= 9999; ++seq) {
        archived = QStringLiteral("%1.%2.log").arg(stem).arg(seq, 3, 10, QLatin1Char('0'));
        if (QFileInfo::exists(m_logDir.filePath(archived)))
            continue;
        renamed = QFile::rename(m_logDir.filePath(m_currentFileName),
                               m_logDir.filePath(archived));
        break;
    }

    if (renamed) {
        m_currentFileName = nextTimestampedName();
        // ensureLogFile() 会为新文件写会话头并把 m_lineCount 置 1。此处**绝不能再
        // 多写一行**：上一版在这里补写"rotated from"却把计数钉回 1，令实体比计数
        // 多一行，最终单文件冲到 2501 行，把 2500 的上限击穿。轮转的来龙去脉由
        // 存档文件名本身承载，无须额外记录。
        ensureLogFile();
        return;
    }

    // 改不了名（磁盘/权限异常）也要守住行数上限：退回原地重开并清空，
    // 宁可丢这一份存档，也不让单个文件无限长大。
    qWarning().noquote() << "[WidgetToolbar] log rotation failed for" << m_currentFileName
                         << "- restarting the file empty to honour the line limit";
    m_logFile.setFileName(m_logDir.filePath(m_currentFileName));
    if (m_logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        m_lineCount = 0;
        ensureLogFile();
    }
}

QString DebugLogger::formatLine(const QDateTime &time, Level level,
                                const QString &component, const QString &message)
{
    static const char *names[] = {"TRACE", "DEBUG", "INFO ", "WARN ", "ERROR"};
    const int idx = qBound(0, static_cast<int>(level), 4);
    return QStringLiteral("[%1] [%2] [%3] %4")
        .arg(time.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz")),
             QLatin1String(names[idx]),
             component.isEmpty() ? QStringLiteral("general") : component,
             message);
}

void DebugLogger::writeToFile(const QString &line)
{
    if (!m_logFile.isOpen())
        return;
    QTextStream out(&m_logFile);
    out << line << '\n';
    // 每条都 flush：面板可能被 kwin/dde-shell 直接杀掉，缓冲里的尾部日志会全丢，
    // 而排障要的往往正是最后那几行。日志量已被跃变策略压低，代价可接受。
    out.flush();
}
