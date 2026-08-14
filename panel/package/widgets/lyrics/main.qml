// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 内置小组件：端闱乐部歌词（默认 4×2，占满一行）
// 数据来自宿主能力代理 Lyrics（org.deepin.widgettoolbar）：
// 会话 D-Bus 订阅 org.mpris.MediaPlayer2.ter_music 的 A/B 双缓冲歌词快照，
// 按槽位固定布局：A 槽居左、B 槽居右，随 active_line 交替高亮，
// 并处理未启动/未播放/无歌词三种状态。
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

    // 标题行：应用图标 + 标题 + 连接状态圆点
    RowLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 12
            rightMargin: 12
        }
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

    // 两行歌词：A 槽居左、B 槽居右，活动槽高亮、另一槽弱化，体现 A/B 双缓冲
    ColumnLayout {
        anchors {
            top: parent.top
            topMargin: 34
            left: parent.left
            leftMargin: 12
            right: parent.right
            rightMargin: 12
            bottom: parent.bottom
            bottomMargin: 10
        }
        spacing: 8
        visible: Lyrics.connected && Lyrics.hasTrack && Lyrics.hasLyrics

        // A 槽（居左）：active_line 为 A 时高亮
        Text {
            id: slotA
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineAText.length > 0 ? Lyrics.lineAText : "· · ·"
            font: Lyrics.activeLineA ? DTK.fontManager.t4 : DTK.fontManager.t6
            color: Lyrics.activeLineA ? palette.highlight : palette.windowText
            opacity: Lyrics.activeLineA ? 1.0 : 0.55
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        // B 槽（居右）：active_line 为 B 时高亮
        Text {
            id: slotB
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineBText.length > 0 ? Lyrics.lineBText : "· · ·"
            font: Lyrics.activeLineA ? DTK.fontManager.t6 : DTK.fontManager.t4
            color: Lyrics.activeLineA ? palette.windowText : palette.highlight
            opacity: Lyrics.activeLineA ? 0.55 : 1.0
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

    }

    // 空态提示：未启动 / 未播放 / 无歌词（独立于歌词列，避免随歌词列隐藏）
    Text {
        anchors {
            top: parent.top
            topMargin: 34
            left: parent.left
            leftMargin: 12
            right: parent.right
            rightMargin: 12
            bottom: parent.bottom
            bottomMargin: 10
        }
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
