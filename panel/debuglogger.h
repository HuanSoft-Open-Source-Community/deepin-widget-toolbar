// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QMutex>
#include <QObject>
#include <QString>

/**
 * 面板调试日志单例。
 *
 * 落盘目录：~/.cache/logs/deepin-widget-toolbar/
 * 文件名带时间戳（yyyyMMdd_HHmmss.log），单文件满 2500 行即另起新文件，
 * 满额切换时旧文件改名为 <原名>.<序号>.log 存档。
 *
 * 是否写盘完全由 DConfig 键 debugMode 决定（缺省关闭）；未开启时 log() 直接
 * 返回，既不构造字符串也不触碰文件系统。
 *
 * 锁约定（m_mutex 非递归，务必遵守）：
 *   public 入口（setEnabled / log / logThrottled / flushAndRotate /
 *   currentLogPath）自行加锁；
 *   private 方法（ensureLogFile / checkRotation / writeToFile /
 *   nextTimestampedName）要求**调用方已持锁**，其内部一律不得再加锁，也不得
 *   回调任何 public 加锁方法，否则自死锁。
 */
class DebugLogger : public QObject
{
    Q_OBJECT
public:
    /** Single instance accessor (thread-safe). */
    static DebugLogger *instance();

    /** Log severity levels. */
    enum class Level {
        Trace = 0,   ///< Detailed tracing (function entry/exit, loops)
        Debug = 1,   ///< Feature-level debugging information
        Info = 2,    ///< Routine user-visible events
        Warning = 3, ///< Unexpected conditions requiring attention
        Error = 4    ///< Actual errors that affect functionality
    };

    /** 单文件行数硬上限：写满即轮转，绝不突破（重启续写同一文件时也受约束）。 */
    static constexpr int kMaxLinesPerFile = 2500;

    /** Check if logging is enabled (controlled by DConfig debugMode). */
    bool isEnabled() const;

    /** Enable or disable logging entirely. */
    void setEnabled(bool enabled);

    /** Get the path to the current log file being written. */
    QString currentLogPath() const;

    /** 当前活动日志文件的实际行数（含重启前已存在的内容）。 */
    int currentFileLines() const;

    /** Manually flush and trigger rotation check. */
    void flushAndRotate();

    /** Get total lines written since session start. */
    qint64 totalLinesWritten() const;

    /** 日志根目录，供界面提示与外部工具定位。 */
    static QString logDirectoryPath();

public Q_SLOTS:
    /** Send a log message at various levels. */
    void log(Level level, const QString &component, const QString &message);

    /**
     * 限频日志：同一 key 在 intervalMs 内最多落一条，超出部分丢弃并累计计数，
     * 下次真正写入时把"此前已抑制 N 条"补进消息。供将来确需周期心跳的场景使用；
     * 当前面板逻辑一律用 log() 记跃变，不用它记心跳。
     */
    void logThrottled(const QString &key, int intervalMs, Level level,
                      const QString &component, const QString &message);

private:
    explicit DebugLogger(QObject *parent = nullptr);
    ~DebugLogger();

    DebugLogger(const DebugLogger &) = delete;
    DebugLogger &operator=(const DebugLogger &) = delete;

    /** Rotate log file if line limit reached. 调用方须已持锁。 */
    void checkRotation(bool force = false);

    /** Write a single formatted log line to the current file. 调用方须已持锁。 */
    void writeToFile(const QString &line);

    /** Create/update the log directory and filename. 调用方须已持锁。 */
    void ensureLogFile();

    /** 生成新的时间戳文件名；若同名已存在则追加 _N 以免撞名。调用方须已持锁。 */
    QString nextTimestampedName() const;

    /** Format a log line with timestamp, level, component, and message. */
    static QString formatLine(const QDateTime &time, Level level,
                              const QString &component, const QString &message);

    /** 统计已有文本文件行数，用于重启续写时正确初始化行计数。 */
    static int countLinesIn(const QString &path);

    // ===== Member variables =====
    mutable QMutex m_mutex;            // 保护以下全部状态（含 const 方法内的加锁）
    bool m_enabled = false;            // Overall logging switch
    QFile m_logFile;                   // Current log file handle
    int m_lineCount = 0;               // 当前文件实际行数（初始化时计入既有内容）
    QDir m_logDir;                     // ~/.cache/logs/deepin-widget-toolbar
    QString m_currentFileName;         // Current file name (yyyyMMdd_HHmmss.log)
    qint64 m_totalLines = 0;           // Total lines written since startup
    QHash<QString, QDateTime> m_lastWritten;   // logThrottled 的 key -> 上次写入时刻
    QHash<QString, qint64> m_suppressed;       // logThrottled 的 key -> 已抑制条数
};

/**
 * 分级日志宏。外层 isEnabled 判断不可省：message 实参常是 QString::arg 链，
 * 关掉调试时应连字符串构造一起跳过，而不是构造完再丢进被丢弃的调用。
 */
#define DEBUG_LOG(component, message) \
    do { if (DebugLogger::instance()->isEnabled()) \
         DebugLogger::instance()->log(DebugLogger::Level::Info, QStringLiteral(#component), (message)); } while(0)

#define DEBUG_TRACE(component, message) \
    do { if (DebugLogger::instance()->isEnabled()) \
         DebugLogger::instance()->log(DebugLogger::Level::Trace, QStringLiteral(#component), (message)); } while(0)

#define DEBUG_DETAIL(component, message) \
    do { if (DebugLogger::instance()->isEnabled()) \
         DebugLogger::instance()->log(DebugLogger::Level::Debug, QStringLiteral(#component), (message)); } while(0)

/**
 * 告警/错误：既入日志文件（受 debugMode 门控），也**始终**输出 stderr。
 * 保留 stderr 是刻意的——线上 dde-shell 以 QT_LOGGING_RULES=*.info=false 运行，
 * 关掉调试开关时排障仍需能看到异常信号，不能被开关吞掉。
 */
#define DEBUG_WARNING(component, message) \
    do { \
        const QString _dwt_msg = (message); \
        DebugLogger::instance()->log(DebugLogger::Level::Warning, QStringLiteral(#component), _dwt_msg); \
        qWarning().noquote() << "[WidgetToolbar]" << #component << _dwt_msg; \
    } while(0)

#define DEBUG_ERROR(component, message) \
    do { \
        const QString _dwt_msg = (message); \
        DebugLogger::instance()->log(DebugLogger::Level::Error, QStringLiteral(#component), _dwt_msg); \
        qCritical().noquote() << "[WidgetToolbar]" << #component << _dwt_msg; \
    } while(0)
