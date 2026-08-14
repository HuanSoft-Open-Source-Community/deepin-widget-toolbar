// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>

// 端闱乐部歌词数据源（QML 单例 org.deepin.widgettoolbar/Lyrics）：
// 通过会话 D-Bus 订阅 org.mpris.MediaPlayer2.ter_music 的
// org.yxzl.ter_music.Lyrics 接口（GetLyrics / LyricsChanged），
// 解析 A/B 双缓冲歌词快照，向小组件暴露当前句与下一句。
//
// 这是宿主提供的系统 D-Bus 能力代理：小组件自身不允许直接访问 D-Bus，
// 统一经由本代理完成连接、订阅、解析与降级。
class LyricsSource : public QObject
{
    Q_OBJECT
    // 播放器是否持有 MPRIS 会话总线名（即端闱乐部是否在运行）
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // 是否有曲目在播放（track_id 非空）
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY lyricsChanged)
    // 当前曲目是否加载了歌词
    Q_PROPERTY(bool hasLyrics READ hasLyrics NOTIFY lyricsChanged)
    // 歌词是否带 LRC 时间戳
    Q_PROPERTY(bool hasTimestamps READ hasTimestamps NOTIFY lyricsChanged)
    // 当前句（active_line 指向槽位的文本）
    Q_PROPERTY(QString activeText READ activeText NOTIFY lyricsChanged)
    // 下一句（另一槽位的文本）
    Q_PROPERTY(QString nextText READ nextText NOTIFY lyricsChanged)
    // A/B 双缓冲槽位文本：供小组件按槽位固定布局（如左/右两行交替高亮）
    Q_PROPERTY(QString lineAText READ lineAText NOTIFY lyricsChanged)
    Q_PROPERTY(QString lineBText READ lineBText NOTIFY lyricsChanged)
    // 当前活动槽是否为 A（active_line == "A"；active_line 为 null 时按 A 处理）
    Q_PROPERTY(bool activeLineA READ activeLineA NOTIFY lyricsChanged)
    // 当前曲目的 mpris:trackid
    Q_PROPERTY(QString trackId READ trackId NOTIFY lyricsChanged)

public:
    explicit LyricsSource(QObject *parent = nullptr);

    bool connected() const;
    bool hasTrack() const;
    bool hasLyrics() const;
    bool hasTimestamps() const;
    QString activeText() const;
    QString nextText() const;
    QString lineAText() const;
    QString lineBText() const;
    bool activeLineA() const;
    QString trackId() const;

    // 主动拉取一次歌词快照（订阅信号之外的兜底刷新）
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void connectedChanged();
    void lyricsChanged();

private Q_SLOTS:
    void onServiceRegistered(const QString &service);
    void onServiceUnregistered(const QString &service);
    void onLyricsChanged(const QString &payload);

private:
    void applySnapshot(const QString &payload);
    void resetSnapshot();

    bool m_connected = false;
    bool m_hasTrack = false;
    bool m_hasLyrics = false;
    bool m_hasTimestamps = false;
    QString m_activeText;
    QString m_nextText;
    QString m_lineAText;
    QString m_lineBText;
    bool m_activeLineA = true;
    QString m_trackId;
    // 上次快照原文：接口文档保证内容变化才发信号，这里按原文去重，
    // 等价于用 revision 丢弃重复/过期更新
    QString m_lastPayload;
};
