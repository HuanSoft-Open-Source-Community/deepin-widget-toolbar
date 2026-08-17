// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 可复用指针表盘：clock 与世界时钟共用。
// utcOffset 以小时为单位（支持半小时等非整小时时区）；
// showLabels 控制表盘下方文字；
// highlighted 用于区分本机时区。
// preloadTime 开启时订阅宿主 ClockTime 的整秒广播，表盘只更新指针旋转，
// 静态表盘缓存为单个 Canvas，不随秒针重绘。
// 指针按整秒步进（不插值）：所有表盘在同一 ClockTime 广播时刻跳动，
// 每秒仅一次重绘，避免数十根指针各自运行 1000ms 旋转动画把场景图
// 渲染逼到 vsync 常驻（17 个表盘时实测 ~13% 单核 → 趋近于 0）。
Item {
    id: root

    property real utcOffset: 0
    property string label: ""
    property bool showLabels: true
    property bool highlighted: false
    property color accentColor: palette.highlight
    property color faceBackgroundColor: "#ffffff"
    // 透明表盘：开启时不绘制表盘底色（配色模式改造前即无底色），圆环/刻度/指针保留
    property bool transparentFace: false
    property color dialColor: "#000000"
    property color hourMinuteHandColor: "#000000"
    property color secondHandColor: "#ff4d4f"
    property color textColor: palette.windowText
    property bool preloadTime: true
    property bool active: true

    property var epochMs: 0
    property real hourAngle: 0
    property real minuteAngle: 0
    property real secondAngle: 0

    readonly property real labelHeight: root.showLabels ? Math.min(20, root.height * 0.16) : 0
    readonly property real radius: Math.max(2,
        Math.min(root.width, Math.max(0, root.height - root.labelHeight)) / 2 - 2)
    readonly property real handWidth: Math.max(1, root.radius * 0.07)

    function timeForOffset(ms) {
        var local = new Date(ms)
        var utcMs = ms + local.getTimezoneOffset() * 60000
        return new Date(utcMs + root.utcOffset * 3600000)
    }

    function applyTime(ms) {
        var now = root.timeForOffset(ms)
        var seconds = now.getSeconds()
        var minutes = now.getMinutes()
        var hours = now.getHours() % 12
        root.hourAngle = (hours + minutes / 60 + seconds / 3600) * 30
        root.minuteAngle = (minutes + seconds / 60) * 6
        root.secondAngle = seconds * 6
    }

    function tick() {
        root.epochMs = root.preloadTime ? ClockTime.epochMs : Date.now()
        root.applyTime(root.epochMs)
    }

    onUtcOffsetChanged: root.tick()
    onVisibleChanged: if (visible) root.tick()
    onActiveChanged: if (root.active) root.tick()
    onPreloadTimeChanged: root.tick()
    onPaletteChanged: dialCanvas.requestPaint()
    onShowLabelsChanged: dialCanvas.requestPaint()
    onFaceBackgroundColorChanged: dialCanvas.requestPaint()
    onTransparentFaceChanged: dialCanvas.requestPaint()
    onDialColorChanged: dialCanvas.requestPaint()
    onHourMinuteHandColorChanged: dialCanvas.requestPaint()
    onSecondHandColorChanged: dialCanvas.requestPaint()
    Component.onCompleted: root.tick()

    Connections {
        target: ClockTime
        enabled: root.preloadTime && root.active && root.visible
        function onEpochMsChanged() {
            root.tick()
        }
    }

    Timer {
        id: fallbackTimer
        interval: 1000
        repeat: true
        running: !root.preloadTime && root.active && root.visible
        onTriggered: root.tick()
    }

    Rectangle {
        id: highlightBox
        anchors.fill: parent
        anchors.bottomMargin: root.labelHeight
        radius: DTK.platformTheme.windowRadius
        color: "transparent"
        border.width: root.highlighted ? 2 : 0
        border.color: root.accentColor
    }

    Item {
        id: faceArea
        anchors.fill: parent
        anchors.bottomMargin: root.labelHeight

        // 静态表盘：圆环与刻度只在尺寸/主题变化时重绘，不随秒针刷新
        Canvas {
            id: dialCanvas
            anchors.fill: parent
            antialiasing: true

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                if (!ctx)
                    return
                ctx.reset()

                var centerX = width / 2
                var centerY = height / 2
                var radius = root.radius
                var tickCount = radius < 28 ? 4 : 12

                // 表盘底色（透明表盘不绘制，露出卡片/背景）
                if (!root.transparentFace) {
                    ctx.fillStyle = root.faceBackgroundColor
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
                    ctx.fill()
                }

                ctx.lineCap = "round"
                ctx.strokeStyle = root.dialColor
                ctx.fillStyle = root.dialColor

                ctx.lineWidth = Math.max(1, radius * 0.04)
                ctx.beginPath()
                ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
                ctx.stroke()

                for (var i = 0; i < tickCount; i++) {
                    var angle = i * Math.PI * 2 / tickCount - Math.PI / 2
                    var isMajor = radius >= 28 && i % 3 === 0
                    var outer = radius - Math.max(1, radius * 0.06)
                    var inner = outer - (isMajor ? radius * 0.12 : radius * 0.06)
                    ctx.lineWidth = isMajor
                        ? Math.max(1.5, radius * 0.05)
                        : Math.max(1, radius * 0.03)
                    ctx.beginPath()
                    ctx.moveTo(centerX + Math.cos(angle) * inner,
                               centerY + Math.sin(angle) * inner)
                    ctx.lineTo(centerX + Math.cos(angle) * outer,
                               centerY + Math.sin(angle) * outer)
                    ctx.stroke()
                }
            }
        }

        // 指针使用场景图矩形 + 旋转，秒针刷新只改 rotation，不再触发软件 Canvas 重绘
        Item {
            id: hourHand
            anchors.fill: parent
            rotation: root.hourAngle

            Rectangle {
                x: parent.width / 2 - root.handWidth / 2
                y: parent.height / 2 - root.radius * 0.48
                width: root.handWidth
                height: root.radius * 0.48
                radius: root.handWidth / 2
                color: root.hourMinuteHandColor
            }
        }

        Item {
            id: minuteHand
            anchors.fill: parent
            rotation: root.minuteAngle

            Rectangle {
                x: parent.width / 2 - root.handWidth * 0.8
                y: parent.height / 2 - root.radius * 0.68
                width: root.handWidth * 0.8
                height: root.radius * 0.68
                radius: Math.max(1, root.handWidth * 0.4)
                color: root.hourMinuteHandColor
            }
        }

        Item {
            id: secondHand
            anchors.fill: parent
            rotation: root.secondAngle

            Rectangle {
                x: parent.width / 2 - root.handWidth * 0.35
                y: parent.height / 2 - root.radius * 0.76
                width: root.handWidth * 0.7
                height: root.radius * 0.76
                radius: Math.max(1, root.handWidth * 0.35)
                color: root.secondHandColor
            }
        }

        Rectangle {
            x: parent.width / 2 - Math.max(1.5, root.radius * 0.05)
            y: parent.height / 2 - Math.max(1.5, root.radius * 0.05)
            width: Math.max(3, root.radius * 0.1)
            height: Math.max(3, root.radius * 0.1)
            radius: Math.max(1.5, root.radius * 0.05)
            color: root.secondHandColor
        }
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.labelHeight
        visible: root.showLabels
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.label
        font.pixelSize: Math.max(7, Math.min(13, parent.width * 0.035))
        color: root.highlighted ? root.accentColor : root.textColor
        elide: Text.ElideRight
    }
}