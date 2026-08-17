// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置示例小组件：数字/指针双模式时钟（默认数字、2×2）
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    property bool analogMode: widgetConfig && widgetConfig.clockMode === "analog"
    property bool preloadTime: widgetConfig && widgetConfig.preloadTime !== undefined
        ? widgetConfig.preloadTime : true
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#000000")
    textColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.textColor, "#ffffff")
    property color dialBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.dialBackgroundColor, "#ffffff")
    property color dialColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.dialColor, "#000000")
    property color hourMinuteHandColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.hourMinuteHandColor, "#000000")
    property color secondHandColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.secondHandColor, "#ff4d4f")
    highlightColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.highlightColor, "#4d8cff")
    property bool panelVisible: Panel.visible
    property int contentWidth: Math.max(1, width - margin * 2)
    property int contentHeight: Math.max(1, height - margin * 2)
    property bool compact: contentWidth < 70 || contentHeight < 70
    property int timePixelSize: Math.max(12, Math.min(72,
        Math.round(Math.min(contentWidth, contentHeight) * 0.20)))
    property int datePixelSize: Math.max(8, Math.min(22,
        Math.round(Math.min(contentWidth, contentHeight) * 0.065)))

    function refresh() {
        var now = new Date(root.preloadTime ? ClockTime.epochMs : Date.now())
        timeText.text = Qt.formatTime(now, root.compact ? "HH:mm" : "HH:mm:ss")
        dateText.text = Qt.formatDate(now, Qt.DefaultLocaleLongDate)
    }

    Column {
        visible: !root.analogMode
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.timePixelSize
            color: root.effectiveTransparent ? root.themeTextColor : palette.windowText
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.compact
            font.pixelSize: root.datePixelSize
            color: root.effectiveTransparent ? root.themeTextColor : palette.windowText
            opacity: 0.7
        }
    }

    Components.AnalogClock {
        id: analogFace
        visible: root.analogMode
        anchors.fill: parent
        utcOffset: 0
        showLabels: false
        accentColor: root.highlightColor
        faceBackgroundColor: root.dialBackgroundColor
        // 透明模式下不绘制表盘底色（配色模式前样式）
        transparentFace: root.effectiveTransparent
        dialColor: root.dialColor
        hourMinuteHandColor: root.hourMinuteHandColor
        secondHandColor: root.secondHandColor
        textColor: root.textColor
        preloadTime: root.preloadTime
        active: root.analogMode && root.panelVisible
    }

    Connections {
        target: ClockTime
        enabled: root.preloadTime && root.panelVisible && root.visible
        function onEpochMsChanged() {
            root.refresh()
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.preloadTime && root.panelVisible && root.visible
        onTriggered: root.refresh()
    }

    onVisibleChanged: if (visible) root.refresh()
    onPanelVisibleChanged: if (panelVisible) root.refresh()
    onPreloadTimeChanged: root.refresh()
    Component.onCompleted: root.refresh()
}
