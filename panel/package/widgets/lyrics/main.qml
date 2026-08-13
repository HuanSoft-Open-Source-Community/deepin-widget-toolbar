// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 内置小组件：端闱乐部歌词（默认 4×2，占满一行）
// 数据来自宿主能力代理 Lyrics（org.deepin.widgettoolbar）：
// 会话 D-Bus 订阅 org.mpris.MediaPlayer2.ter_music 的歌词快照，
// 展示当前句（高亮）与下一句（弱化），并处理未启动/未播放/无歌词三种状态。
Item {
    id: root

    // 空态/降级提示：仅当无需展示歌词时非空
    property string statusText: {
        if (!Lyrics.connected)
            return qsTr("Start Ter-Music and play a song to show lyrics")
        if (!Lyrics.hasTrack)
            return qsTr("Ter-Music is not playing")
        if (!Lyrics.hasLyrics)
            return qsTr("This track has no lyrics")
        return ""
    }

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // 标题行：应用图标 + 标题 + 连接状态圆点
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Image {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: "media-player"
                sourceSize.width: 16
                sourceSize.height: 16
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Ter-Music Lyrics")
                font: DTK.fontManager.t6
                color: palette.windowText
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: Lyrics.connected
                    ? Qt.rgba(0.35, 0.78, 0.42, 1)
                    : Qt.rgba(0.5, 0.5, 0.5, 0.55)
            }
        }

        // 当前句：高亮色，纵向居中占满剩余空间
        Text {
            id: activeLine
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: Text.AlignVCenter
            visible: Lyrics.connected && Lyrics.hasTrack && Lyrics.hasLyrics
            text: Lyrics.activeText.length > 0 ? Lyrics.activeText : "· · ·"
            font: DTK.fontManager.t4
            color: palette.highlight
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // 下一句：弱化显示（无时间戳歌词中即 B 槽的第二行）
        Text {
            id: nextLine
            Layout.fillWidth: true
            visible: Lyrics.connected && Lyrics.hasTrack && Lyrics.hasLyrics
                && Lyrics.nextText.length > 0
            text: Lyrics.nextText
            font: DTK.fontManager.t6
            color: palette.windowText
            opacity: 0.55
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // 空态提示：未启动 / 未播放 / 无歌词
        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            visible: root.statusText.length > 0
            text: root.statusText
            font: DTK.fontManager.t6
            color: palette.windowText
            opacity: 0.6
            wrapMode: Text.Wrap
        }
    }
}
