// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariant>

#include <atomic>

class QNetworkAccessManager;
class QNetworkReply;
class QSaveFile;

// 宿主提供给小组件的网络访问代理（QML 单例 org.deepin.widgettoolbar/Network）：
// 仅放行 https（测试钩子可临时放开 http），JSON 拉取带 TTL 内存缓存，
// 下载落盘与 FileIO 完全同沙箱根，防止第三方小组件触达任意本机路径或明文信道。
class Network : public QObject
{
    Q_OBJECT
public:
    explicit Network(QObject *parent = nullptr);
    ~Network() override;

    // 允许下载落盘的根目录（语义同 FileIO::setAllowedRoot），由宿主初始化时注入
    void setAllowedRoot(const QString &path);

    // —— 测试钩子（public C++ 方法，不参与 QML 契约）——
    // 传输超时（默认 15000ms），供超时用例缩短到可控时长
    void setRequestTimeoutMs(int ms);
    // 临时放行 http（默认 false）：生产代码路径绝不允许 http，仅供本地 mock 用例
    void setAllowHttpForTest(bool allow);

    // 拉取 JSON：返回 requestId（原子递增）；完成（含缓存命中）后发 jsonFinished，
    // data 为 QJsonDocument::toVariant() 结果；ttlSeconds<=0 表示完全绕过缓存
    Q_INVOKABLE int getJson(const QString &url, int ttlSeconds = 600);
    // 二进制下载落盘（自动创建父目录，QSaveFile 原子提交）：完成后发 downloadFinished
    Q_INVOKABLE int download(const QString &url, const QString &destPath);

Q_SIGNALS:
    void jsonFinished(int requestId, bool success, const QVariant &data,
                      const QString &errorCode, int httpStatus);
    void downloadFinished(int requestId, bool success, const QString &destPath,
                          const QString &errorCode, int httpStatus);

private:
    struct CacheEntry {
        QVariant data;
        QDateTime expiry;
    };

    // 在途请求状态：readyRead 与 finished 两个回调共享
    struct Pending {
        enum Kind { Json, Download };
        int id = 0;
        Kind kind = Json;
        QString cacheKey;     // Json：TTL 缓存键（URL 串）
        int ttlSeconds = 0;   // Json：>0 时成功后写内存缓存
        QString destPath;     // Download：落盘目标
        QByteArray body;      // Json：响应体累积（上限 1MB）
        QSaveFile *file = nullptr;   // Download：原子落盘句柄
        qint64 received = 0;  // Download：已落盘字节
        bool tooLarge = false;       // 超响应上限主动中止过
        bool localError = false;     // 建目录/打开/写入本地 IO 失败
    };

    enum class UrlCheck { Ok, Invalid, NotAllowedScheme };

    UrlCheck checkUrl(const QUrl &url) const;
    bool isPathAllowed(const QString &path) const;
    void issueRequest(const QUrl &url, const Pending &pending);
    bool ensureDownloadFile(Pending &p);
    void onReplyReadyRead(QNetworkReply *reply);
    void finishJson(QNetworkReply *reply);
    void finishDownload(QNetworkReply *reply);

    QNetworkAccessManager *m_nam = nullptr;
    QString m_allowedRoot;
    int m_requestTimeoutMs = 15000;
    bool m_allowHttpForTest = false;
    std::atomic<int> m_nextRequestId { 0 };
    QHash<QString, CacheEntry> m_jsonCache;
    QHash<QNetworkReply *, Pending> m_pending;
};
