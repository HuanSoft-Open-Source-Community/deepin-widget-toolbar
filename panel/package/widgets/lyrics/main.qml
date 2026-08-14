// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：端闱乐部歌词（默认 4×2，占满一行）
// 支持按实例配置字体族与基础颜色；数据仍由宿主 Lyrics 代理提供。
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
    property string lyricFontFamily: widgetConfig && widgetConfig.lyricsFont
        ? widgetConfig.lyricsFont : DTK.fontManager.t4.family
    property string lyricColor: widgetConfig && widgetConfig.lyricsColor
        ? widgetConfig.lyricsColor : "auto"
    property int contentHeight: Math.max(1, height - margin * 2)
    property int activePixelSize: Math.max(13, Math.min(42,
        Math.round(contentHeight * 0.105)))
    property int inactivePixelSize: Math.max(11, Math.min(32,
        Math.round(contentHeight * 0.078)))

    property string statusText: {
        if (!Lyrics.connected)
            return qsTr("Start Ter-Music and play a song to show lyrics")
        if (!Lyrics.hasTrack)
            return qsTr("Ter-Music is not playing")
        if (!Lyrics.hasLyrics)
            return qsTr("This track has no lyrics")
        return ""
    }

    function textColor(active) {
        if (root.lyricColor !== "auto")
            return root.lyricColor
        return active ? palette.highlight : palette.windowText
    }

    // 标题行：应用图标 + 标题 + 连接状态圆点
    RowLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 2
            leftMargin: 2
            rightMargin: 2
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

    ColumnLayout {
        anchors {
            top: parent.top
            topMargin: 26
            left: parent.left
            leftMargin: 2
            right: parent.right
            rightMargin: 2
            bottom: parent.bottom
            bottomMargin: 2
        }
        spacing: 8
        visible: Lyrics.connected && Lyrics.hasTrack && Lyrics.hasLyrics

        Text {
            id: slotA
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineAText.length > 0 ? Lyrics.lineAText : "· · ·"
            font.family: root.lyricFontFamily
            font.pixelSize: Lyrics.activeLineA
                ? root.activePixelSize : root.inactivePixelSize
            color: root.textColor(Lyrics.activeLineA)
            opacity: Lyrics.activeLineA ? 1.0 : 0.55
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        Text {
            id: slotB
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineBText.length > 0 ? Lyrics.lineBText : "· · ·"
            font.family: root.lyricFontFamily
            font.pixelSize: Lyrics.activeLineA
                ? root.inactivePixelSize : root.activePixelSize
            color: root.textColor(!Lyrics.activeLineA)
            opacity: Lyrics.activeLineA ? 0.55 : 1.0
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    Text {
        anchors {
            top: parent.top
            topMargin: 26
            left: parent.left
            leftMargin: 2
            right: parent.right
            rightMargin: 2
            bottom: parent.bottom
            bottomMargin: 2
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
