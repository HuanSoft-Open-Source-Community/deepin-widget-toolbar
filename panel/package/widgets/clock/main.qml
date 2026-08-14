// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import "../components" as Components

// 内置示例小组件：数字/指针双模式时钟（默认数字、2×2）
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
    property bool analogMode: widgetConfig && widgetConfig.clockMode === "analog"
    property int contentWidth: Math.max(1, width - margin * 2)
    property int contentHeight: Math.max(1, height - margin * 2)
    property bool compact: contentWidth < 70 || contentHeight < 70
    property int timePixelSize: Math.max(12, Math.min(72,
        Math.round(Math.min(contentWidth, contentHeight) * 0.20)))
    property int datePixelSize: Math.max(8, Math.min(22,
        Math.round(Math.min(contentWidth, contentHeight) * 0.065)))

    Column {
        visible: !root.analogMode
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.timePixelSize
            color: palette.windowText
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.compact
            font.pixelSize: root.datePixelSize
            color: palette.windowText
            opacity: 0.7
        }
    }

    Components.AnalogClock {
        id: analogFace
        visible: root.analogMode
        anchors.fill: parent
        utcOffset: 0
        showLabels: false
        accentColor: palette.highlight
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date()
            timeText.text = Qt.formatTime(now, root.compact ? "HH:mm" : "HH:mm:ss")
            dateText.text = Qt.formatDate(now, Qt.DefaultLocaleLongDate)
            if (root.analogMode) {
                analogFace.requestPaint()
            }
        }
    }
}
