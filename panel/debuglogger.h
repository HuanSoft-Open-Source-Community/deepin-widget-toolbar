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

#include <atomic>

/**
 * 面板调试日志单例。
 *
 * 落盘目录：~/.cache/logs/deepin-widget-toolbar/
 * 文件名带时间戳（yyyyMMdd_HHmmss.log），单文件满 2500 行即另起新文件，
 * 满额切换时旧文件改名为 <原名>.<序号>.log 存档；目录内日志文件总数
 * （含当前活动文件）上限 kMaxLogFiles，超出即按修改时间删除最旧的。
 *
 * 是否写盘完全由 DConfig 键 debugMode 决定（缺省关闭）；未开启时 log() 直接
 * 返回，不构造字符串，也**不创建日志目录**（目录在首次真正写盘时惰性创建）。
 *
 * 锁约定（m_mutex 非递归，务必遵守）：
 *   public 入口（setEnabled / log）自行加锁；
 *   private 方法（ensureLogFile / checkRotation / writeToFile /
 *   pruneArchives / nextTimestampedName）要求**调用方已持锁**，其内部一律不得
 *   再加锁，也不得回调任何 public 加锁方法，否则自死锁。
 *   isEnabled() 例外：读原子量、不加锁，可在任意上下文调用。
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

    /** 目录内日志文件总数上限（含当前活动文件）：超出即删最旧的，避免长期开启累积。 */
    static constexpr int kMaxLogFiles = 20;

    /** Check if logging is enabled (controlled by DConfig debugMode). 免锁。 */
    bool isEnabled() const;

    /** Enable or disable logging entirely. */
    void setEnabled(bool enabled);

public Q_SLOTS:
    /** Send a log message at various levels. */
    void log(Level level, const QString &component, const QString &message);

private:
    explicit DebugLogger(QObject *parent = nullptr);
    ~DebugLogger();

    DebugLogger(const DebugLogger &) = delete;
    DebugLogger &operator=(const DebugLogger &) = delete;

    /** 日志根目录（仅内部使用：目录在首次写盘时惰性创建）。 */
    static QString logDirectoryPath();

    /** Rotate log file if line limit reached. 调用方须已持锁。 */
    void checkRotation(bool force = false);

    /** 只保留最新的 kMaxLogFiles 个日志文件（含活动文件）。调用方须已持锁。 */
    void pruneLogFiles();

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
    mutable QMutex m_mutex;            // 保护文件句柄与路径等状态
    std::atomic_bool m_enabled{false}; // 开关：原子量，isEnabled() 免锁读
    QFile m_logFile;                   // Current log file handle
    int m_lineCount = 0;               // 当前文件实际行数（初始化时计入既有内容）
    QDir m_logDir;                     // ~/.cache/logs/deepin-widget-toolbar
    QString m_currentFileName;         // Current file name (yyyyMMdd_HHmmss.log)
};

/**
 * 分级日志宏。外层 isEnabled 判断不可省：message 实参常是 QString::arg 链，
 * 关掉调试时应连字符串构造一起跳过，而不是构造完再丢进被丢弃的调用。
 */
#define DEBUG_LOG(component, message) \
    do { if (DebugLogger::instance()->isEnabled()) \
         DebugLogger::instance()->log(DebugLogger::Level::Info, QStringLiteral(#component), (message)); } while(0)

/**
 * 组件名需要运行时构造（非字面量）时的守卫版本；同样保证关闭时不构造消息串。
 * 用法：DEBUG_GUARDED(Debug, QStringLiteral("widgetmanager"), ...)。
 */
#define DEBUG_GUARDED(level, component, message) \
    do { if (DebugLogger::instance()->isEnabled()) \
         DebugLogger::instance()->log(DebugLogger::Level::level, (component), (message)); } while(0)

/**
 * 告警：既入日志文件（受 debugMode 门控），也**始终**输出 stderr。
 * 保留 stderr 是刻意的——线上 dde-shell 以 QT_LOGGING_RULES=*.info=false 运行，
 * 关掉调试开关时排障仍需能看到异常信号，不能被开关吞掉。
 */
#define DEBUG_WARNING(component, message) \
    do { \
        const QString _dwt_msg = (message); \
        DebugLogger::instance()->log(DebugLogger::Level::Warning, QStringLiteral(#component), _dwt_msg); \
        qWarning().noquote() << "[WidgetToolbar]" << #component << _dwt_msg; \
    } while(0)
