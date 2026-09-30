// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "network.h"

#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QMetaObject>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
constexpr qint64 kMaxJsonBytes = 1024 * 1024;          // getJson 响应上限 1MB
constexpr qint64 kMaxDownloadBytes = 32 * 1024 * 1024; // download 落盘上限 32MB
constexpr char kUserAgent[] = "deepin-widget-toolbar/1.8";
}

Network::Network(QObject *parent)
    : QObject(parent)
{
    m_nam = new QNetworkAccessManager(this);
    // 重定向策略挂管理器上（Qt 6.8 起移除了 QNetworkRequest::setRedirectPolicy）：
    // 只允许同等或更安全协议的重定向（https→https，禁降级明文）
    m_nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
    // 磁盘缓存：TTL 内存缓存之外的第二层（CacheLocation 下以插件 id 命名空间隔离，上限 64MB；
    // 显式带插件 id 而非裸 http-cache，避免与宿主 dde-shell 进程的同名缓存混居，卸载脚本可定点清理）
    auto *diskCache = new QNetworkDiskCache(m_nam);
    diskCache->setCacheDirectory(
        QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/org.deepin.ds.widgettoolbar/http-cache"));
    diskCache->setMaximumCacheSize(64LL * 1024 * 1024);
    m_nam->setCache(diskCache);
}

Network::~Network()
{
    // 收尾：中断在途请求并丢弃未提交的临时落盘文件，不给事件循环留尾巴
    const auto replies = m_pending.keys();
    for (QNetworkReply *reply : replies) {
        disconnect(reply, nullptr, this, nullptr);
        delete m_pending.take(reply).file;
        reply->abort();
        reply->deleteLater();
    }
}

void Network::setAllowedRoot(const QString &path)
{
    m_allowedRoot = QDir(path).absolutePath();
}

void Network::setRequestTimeoutMs(int ms)
{
    m_requestTimeoutMs = ms;
}

void Network::setAllowHttpForTest(bool allow)
{
    m_allowHttpForTest = allow;
}

int Network::getJson(const QString &urlString, int ttlSeconds)
{
    const int id = m_nextRequestId.fetch_add(1) + 1;

    QUrl url(urlString);
    switch (checkUrl(url)) {
    case UrlCheck::Invalid:
        Q_EMIT jsonFinished(id, false, QVariant(), QStringLiteral("invalid-url"), 0);
        return id;
    case UrlCheck::NotAllowedScheme:
        Q_EMIT jsonFinished(id, false, QVariant(), QStringLiteral("scheme-not-https"), 0);
        return id;
    case UrlCheck::Ok:
        break;
    }

    Pending p;
    p.id = id;
    p.kind = Pending::Json;
    p.ttlSeconds = ttlSeconds;

    // TTL 内存缓存：命中且未过期直接回调，不发网络请求；ttlSeconds<=0 完全绕过缓存
    if (ttlSeconds > 0) {
        p.cacheKey = url.toString();
        const auto it = m_jsonCache.constFind(p.cacheKey);
        if (it != m_jsonCache.constEnd()) {
            if (it->expiry > QDateTime::currentDateTime()) {
                Q_EMIT jsonFinished(id, true, it->data, QString(), 200);
                return id;
            }
            m_jsonCache.erase(it);
        }
    }

    issueRequest(url, p);
    return id;
}

int Network::download(const QString &urlString, const QString &destPath)
{
    const int id = m_nextRequestId.fetch_add(1) + 1;

    QUrl url(urlString);
    switch (checkUrl(url)) {
    case UrlCheck::Invalid:
        Q_EMIT downloadFinished(id, false, destPath, QStringLiteral("invalid-url"), 0);
        return id;
    case UrlCheck::NotAllowedScheme:
        Q_EMIT downloadFinished(id, false, destPath, QStringLiteral("scheme-not-https"), 0);
        return id;
    case UrlCheck::Ok:
        break;
    }

    // 沙箱：与 FileIO 同根，拒绝即回调，不发请求
    if (!isPathAllowed(destPath)) {
        qWarning() << "Network: download destination denied by sandbox:" << destPath;
        Q_EMIT downloadFinished(id, false, destPath, QStringLiteral("path-denied"), 0);
        return id;
    }

    Pending p;
    p.id = id;
    p.kind = Pending::Download;
    p.destPath = destPath;
    issueRequest(url, p);
    return id;
}

Network::UrlCheck Network::checkUrl(const QUrl &url) const
{
    if (!url.isValid() || url.isEmpty())
        return UrlCheck::Invalid;
    const QString scheme = url.scheme().toLower();
    if (scheme == QLatin1String("https"))
        return UrlCheck::Ok;
    if (m_allowHttpForTest && scheme == QLatin1String("http"))
        return UrlCheck::Ok;
    return UrlCheck::NotAllowedScheme;
}

bool Network::isPathAllowed(const QString &path) const
{
    if (m_allowedRoot.isEmpty()) {
        qWarning() << "Network: allowed root not set, denying download";
        return false;
    }
    if (path.trimmed().isEmpty())
        return false;
    // 清洗规则：显式拒绝含 ".." 段的输入（canonical 之外的兜底，防前缀拼接逃逸）
    const QStringList segments =
        QDir::fromNativeSeparators(path).split(QLatin1Char('/'), Qt::SkipEmptyParts);
    if (segments.contains(QLatin1String("..")))
        return false;
    // 以下与 FileIO::isAllowed 同规则
    const QString canonical = QFileInfo(path).canonicalFilePath();
    if (canonical.isEmpty()) {
        // 文件尚不存在时 canonical 为空，用绝对路径前缀判断（下载落盘场景）
        const QString abs = QFileInfo(path).absolutePath();
        return abs.startsWith(m_allowedRoot + QLatin1Char('/')) || abs == m_allowedRoot;
    }
    return canonical.startsWith(m_allowedRoot + QLatin1Char('/')) || canonical == m_allowedRoot;
}

void Network::issueRequest(const QUrl &url, const Pending &pending)
{
    QNetworkRequest request(url);
    request.setTransferTimeout(m_requestTimeoutMs);
    request.setRawHeader(QByteArrayLiteral("User-Agent"), kUserAgent);

    QNetworkReply *reply = m_nam->get(request);
    m_pending.insert(reply, pending);
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] {
        onReplyReadyRead(reply);
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        if (m_pending.value(reply).kind == Pending::Json)
            finishJson(reply);
        else
            finishDownload(reply);
    });
}

bool Network::ensureDownloadFile(Pending &p)
{
    if (p.file)
        return true;
    const QFileInfo info(p.destPath);
    if (!info.dir().exists() && !QDir().mkpath(info.absolutePath())) {
        qWarning() << "Network: cannot create parent dirs for" << p.destPath;
        return false;
    }
    p.file = new QSaveFile(p.destPath);
    if (!p.file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "Network: cannot open" << p.destPath << p.file->errorString();
        delete p.file;
        p.file = nullptr;
        return false;
    }
    return true;
}

void Network::onReplyReadyRead(QNetworkReply *reply)
{
    auto it = m_pending.find(reply);
    if (it == m_pending.end())
        return;
    Pending &p = it.value();
    if (p.tooLarge || p.localError)
        return;

    const qint64 limit = p.kind == Pending::Json ? kMaxJsonBytes : kMaxDownloadBytes;

    // 先查 Content-Length 头：超限立即中止，不收整个响应体
    const QVariant contentLength = reply->header(QNetworkRequest::ContentLengthHeader);
    if (contentLength.isValid() && contentLength.toLongLong() > limit) {
        p.tooLarge = true;
        // 队列化 abort：避免同步 finished 重入时改写 m_pending 使引用失效
        QMetaObject::invokeMethod(reply, &QNetworkReply::abort, Qt::QueuedConnection);
        return;
    }

    if (p.kind == Pending::Json) {
        p.body += reply->readAll();
        if (p.body.size() > limit)
            p.tooLarge = true;
        if (p.tooLarge)
            QMetaObject::invokeMethod(reply, &QNetworkReply::abort, Qt::QueuedConnection);
        return;
    }

    // Download：非 2xx 或已出错时不落盘，交给 finished 统一报告
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (reply->error() != QNetworkReply::NoError || status < 200 || status >= 300)
        return;

    if (!ensureDownloadFile(p)) {
        p.localError = true;
        return;
    }
    const QByteArray chunk = reply->readAll();
    if (chunk.isEmpty())
        return;
    if (p.file->write(chunk) != chunk.size()) {
        qWarning() << "Network: write failed for" << p.destPath << p.file->errorString();
        p.localError = true;
        return;
    }
    p.received += chunk.size();
    // 流式累计超限也要中止（Content-Length 缺失/谎报的兜底）
    if (p.received > limit)
        p.tooLarge = true;
    if (p.tooLarge)
        QMetaObject::invokeMethod(reply, &QNetworkReply::abort, Qt::QueuedConnection);
}

void Network::finishJson(QNetworkReply *reply)
{
    if (!m_pending.contains(reply))
        return;
    const Pending p = m_pending.take(reply);
    reply->deleteLater();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto fail = [this, &p, status](const QString &code) {
        Q_EMIT jsonFinished(p.id, false, QVariant(), code, status);
    };

    if (p.tooLarge)
        return fail(QStringLiteral("too-large"));
    // OperationCanceledError 在当前设计里只能由 setTransferTimeout 触发
    // （too-large 的主动 abort 已被上面的标记截获）→ "timeout"；
    // "aborted" 稳定码保留给将来的显式取消通道（如 cancel(requestId)）
    if (reply->error() == QNetworkReply::OperationCanceledError)
        return fail(QStringLiteral("timeout"));
    // HTTP 状态非 2xx 优先于网络层错误：Qt 会把 404 等映射成
    // ContentNotFoundError 之类的传输错误，但语义上应报 "http-<code>"
    const bool badStatus = status != 0 && (status < 200 || status >= 300);
    if (reply->error() != QNetworkReply::NoError)
        return fail(badStatus ? QStringLiteral("http-%1").arg(status)
                              : QStringLiteral("network"));
    if (badStatus)
        return fail(QStringLiteral("http-%1").arg(status));

    QJsonParseError parseError {};
    const QJsonDocument doc = QJsonDocument::fromJson(p.body, &parseError);
    if (doc.isNull()) {
        qWarning() << "Network: json parse failed for" << p.cacheKey
                   << parseError.errorString();
        return fail(QStringLiteral("json-parse"));
    }

    const QVariant data = doc.toVariant();
    if (p.ttlSeconds > 0)
        m_jsonCache.insert(p.cacheKey,
                           { data, QDateTime::currentDateTime().addSecs(p.ttlSeconds) });
    Q_EMIT jsonFinished(p.id, true, data, QString(), status);
}

void Network::finishDownload(QNetworkReply *reply)
{
    if (!m_pending.contains(reply))
        return;
    const Pending p = m_pending.take(reply);
    reply->deleteLater();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QSaveFile *file = p.file;
    const auto fail = [&](const QString &code) {
        if (file) {
            file->cancelWriting();
            delete file;
        }
        Q_EMIT downloadFinished(p.id, false, p.destPath, code, status);
    };

    if (p.localError)
        return fail(QStringLiteral("network"));
    if (p.tooLarge)
        return fail(QStringLiteral("too-large"));
    // OperationCanceledError 在当前设计里只能由 setTransferTimeout 触发
    // （too-large 的主动 abort 已被上面的标记截获）→ "timeout"；
    // "aborted" 稳定码保留给将来的显式取消通道（如 cancel(requestId)）
    if (reply->error() == QNetworkReply::OperationCanceledError)
        return fail(QStringLiteral("timeout"));
    // HTTP 状态非 2xx 优先于网络层错误：Qt 会把 404 等映射成
    // ContentNotFoundError 之类的传输错误，但语义上应报 "http-<code>"
    const bool badStatus = status != 0 && (status < 200 || status >= 300);
    if (reply->error() != QNetworkReply::NoError)
        return fail(badStatus ? QStringLiteral("http-%1").arg(status)
                              : QStringLiteral("network"));
    if (badStatus)
        return fail(QStringLiteral("http-%1").arg(status));

    // 成功：空响应也产出文件，再原子提交
    if (!file) {
        Pending tmp = p;
        if (!ensureDownloadFile(tmp)) {
            delete file;
            return fail(QStringLiteral("network"));
        }
        file = tmp.file;
    }
    if (!file->commit()) {
        qWarning() << "Network: commit failed for" << p.destPath << file->errorString();
        delete file;
        return fail(QStringLiteral("network"));
    }
    delete file;
    Q_EMIT downloadFinished(p.id, true, p.destPath, QString(), status);
}
