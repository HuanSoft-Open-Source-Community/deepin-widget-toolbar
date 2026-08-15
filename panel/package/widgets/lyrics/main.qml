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

    widgetConfig: ({})
    property string lyricFontFamily: widgetConfig && widgetConfig.lyricsFont
        ? widgetConfig.lyricsFont : DTK.fontManager.t4.family
    property string lyricColor: widgetConfig && widgetConfig.lyricsColor
        ? widgetConfig.lyricsColor : "auto"
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#ffffc0cb")
    property color titleTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.titleTextColor, "#7a1f33")
    property color statusTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.statusTextColor, "#7a3b4a")
    property string inactiveTextColor: widgetConfig && widgetConfig.inactiveTextColor
        ? String(widgetConfig.inactiveTextColor) : "#8a4a55"
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
        // 淡粉底固定为浅色，auto 模式必须用深色文字保证可读性
        return active ? "#b0305a" : "#5a2233"
    }

    function inactiveColor(activeColor) {
        if (root.inactiveTextColor !== "auto") {
            var resolved = Components.ColorUtils.resolveColor(root.inactiveTextColor, "")
            if (resolved.length > 0)
                return resolved
        }
        return activeColor
    }

    // 标题行：标题 + 连接状态圆点
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

        Text {
            Layout.fillWidth: true
            text: qsTr("Ter-Music Lyrics")
            font: DTK.fontManager.t6
            color: root.titleTextColor
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
            color: Lyrics.activeLineA
                ? root.textColor(true)
                : root.inactiveColor(root.textColor(false))
            opacity: Lyrics.activeLineA ? 1.0
                : (root.inactiveTextColor === "auto" ? 0.55 : 0.85)
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
            color: root.inactiveColor(root.textColor(!Lyrics.activeLineA))
            opacity: Lyrics.activeLineA
                ? (root.inactiveTextColor === "auto" ? 0.55 : 0.85) : 1.0
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
        color: root.statusTextColor
        opacity: 0.6
        wrapMode: Text.Wrap
    }
}
