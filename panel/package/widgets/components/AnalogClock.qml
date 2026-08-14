// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0

// 可复用指针表盘：clock 与世界时钟共用。
// utcOffset 以小时为单位（支持半小时等非整小时时区）；
// showLabels 控制表盘下方文字；
// highlighted 用于区分本机时区。
Item {
    id: root

    property real utcOffset: 0
    property string label: ""
    property bool showLabels: true
    property bool highlighted: false
    property color accentColor: palette.highlight

    onUtcOffsetChanged: face.requestPaint()

    function clockTime() {
        var now = new Date()
        var utcMs = now.getTime() + now.getTimezoneOffset() * 60000
        return new Date(utcMs + root.utcOffset * 3600000)
    }

    Rectangle {
        id: highlightBox
        anchors.fill: parent
        anchors.bottomMargin: root.showLabels ? Math.min(20, parent.height * 0.16) : 0
        radius: DTK.platformTheme.windowRadius
        color: "transparent"
        border.width: root.highlighted ? 2 : 0
        border.color: root.accentColor
    }

    Canvas {
        id: face
        anchors.fill: parent
        anchors.bottomMargin: root.showLabels ? Math.min(20, parent.height * 0.16) : 0

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            if (!ctx)
                return
            ctx.reset()

            var size = Math.min(width, height)
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.max(2, size / 2 - 2)
            var now = root.clockTime()
            var hour = now.getHours() % 12
            var minute = now.getMinutes()
            var second = now.getSeconds()

            ctx.lineCap = "round"
            ctx.strokeStyle = palette.windowText
            ctx.fillStyle = palette.windowText

            ctx.lineWidth = Math.max(1, radius * 0.04)
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
            ctx.stroke()

            var tickCount = radius < 28 ? 4 : 12
            for (var i = 0; i < tickCount; i++) {
                var angle = i * Math.PI * 2 / tickCount - Math.PI / 2
                var isMajor = radius >= 28 && i % 3 === 0
                var outer = radius - Math.max(1, radius * 0.06)
                var inner = outer - (isMajor ? radius * 0.12 : radius * 0.06)
                ctx.lineWidth = isMajor ? Math.max(1.5, radius * 0.05) : Math.max(1, radius * 0.03)
                ctx.beginPath()
                ctx.moveTo(centerX + Math.cos(angle) * inner, centerY + Math.sin(angle) * inner)
                ctx.lineTo(centerX + Math.cos(angle) * outer, centerY + Math.sin(angle) * outer)
                ctx.stroke()
            }

            function drawHand(value, max, length, widthFactor) {
                var handAngle = value / max * Math.PI * 2 - Math.PI / 2
                ctx.lineWidth = Math.max(1, radius * widthFactor)
                ctx.beginPath()
                ctx.moveTo(centerX, centerY)
                ctx.lineTo(centerX + Math.cos(handAngle) * radius * length,
                           centerY + Math.sin(handAngle) * radius * length)
                ctx.stroke()
            }

            drawHand(hour + minute / 60, 12, 0.48, 0.07)
            drawHand(minute + second / 60, 60, 0.68, 0.05)
            ctx.strokeStyle = root.accentColor
            drawHand(second, 60, 0.76, 0.025)

            ctx.beginPath()
            ctx.arc(centerX, centerY, Math.max(1, radius * 0.05), 0, Math.PI * 2)
            ctx.fill()
        }
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.showLabels ? Math.min(20, parent.height * 0.16) : 0
        visible: root.showLabels
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.label
        font.pixelSize: Math.max(7, Math.min(13, parent.width * 0.035))
        color: root.highlighted ? root.accentColor : palette.windowText
        elide: Text.ElideRight
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: face.requestPaint()
    }
}
