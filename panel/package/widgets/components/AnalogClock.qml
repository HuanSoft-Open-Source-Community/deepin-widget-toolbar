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

    // ── 流光逐图元采样接口（clock / worldtime 接线用）────────────────────
    // 空间参考：卡片宽与本表盘中心相对卡片的 x。Canvas 内把图元的画布局部 x
    // 换算到卡片坐标后按 ColorUtils.spaceOffset(x, flowWidthRef) 取色；
    // flowWidthRef<=0 时 offset 恒 0（退化为整盘单色跑马，不误采样）。
    property real flowWidthRef: 0
    property real flowCenterX: 0
    // 流光元数据：仅当"该部位是整卡唯一 owner 且值为 @flow:"时由调用方置
    // owner=true（判定入口：ColorUtils.flowSiteIsOwner(config,"dials",site)
    // && ColorUtils.isFlow(value)）：
    //   {
    //     face: { owner: bool, base: string }, // 表盘面底色（dialBackgroundColor 键）
    //     dial: { owner: bool, base: string }  // 圆环与刻度（dialColor 键）
    //   }
    // base 为 ColorUtils.flowBase(原始值, 浅色缺省)。owner=false 或 null 时
    // 面/刻度沿用 faceBackgroundColor/dialColor 单色路径，行为与改造前一致；
    // 重绘仍由调用方注入色的低频变化（canvasSiteColor → flowCanvasPhase）
    // 经既有 on*ColorChanged 驱动，≤10fps。指针（场景图矩形）色由调用方
    // 经 resolveSiteColor owner 门控解析后注入，本组件不做逐图元采样。
    property var flowMeta: null

    // Canvas 内逐图元流光取色：localX 为图元在画布内的 x；低频画布相位，
    // 一帧内所有图元共用同一 phase/dark，仅按各自 x 偏移色相。
    function flowColorAtLocal(base, localX, canvasWidth) {
        var xInCard = root.flowCenterX + (localX - canvasWidth / 2)
        return ColorUtils.flowColorAt(base, ColorUtils.flowCanvasPhase,
            ColorUtils.spaceOffset(xInCard, root.flowWidthRef), ColorUtils.dark)
    }

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
    onFlowMetaChanged: dialCanvas.requestPaint()
    // 指针颜色由 Rectangle 直接绑定场景图，不需要重绘 Canvas；
    // 若在此处 requestPaint，流光指针会按 15fps 反复重绘整块表盘。
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

                // 本帧只判一次 owner 流光；owner 时逐图元按自身 x 采样彩虹，
                // 非 owner / 静态色路径与改造前完全一致（只读注入的单色）
                var meta = root.flowMeta
                var faceFlow = !!(meta && meta.face && meta.face.owner && meta.face.base)
                var dialFlow = !!(meta && meta.dial && meta.dial.owner && meta.dial.base)

                // 表盘底色（透明表盘不绘制，露出卡片/背景）；
                // 圆盘为单图元，owner 时按盘中心 x 取色
                if (!root.transparentFace) {
                    ctx.fillStyle = faceFlow
                        ? root.flowColorAtLocal(meta.face.base, centerX, width)
                        : root.faceBackgroundColor
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
                    ctx.fill()
                }

                ctx.lineCap = "round"
                // 圆环是单图元：owner 时按盘中心 x；刻度在下方逐图元取色
                ctx.strokeStyle = dialFlow
                    ? root.flowColorAtLocal(meta.dial.base, centerX, width)
                    : root.dialColor
                ctx.fillStyle = dialFlow
                    ? root.flowColorAtLocal(meta.dial.base, centerX, width)
                    : root.dialColor

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
                    // 逐刻度按自身 x（内外中点）换算到卡片坐标采样，形成横向彩虹
                    ctx.strokeStyle = dialFlow
                        ? root.flowColorAtLocal(meta.dial.base,
                            centerX + Math.cos(angle) * (inner + outer) / 2, width)
                        : root.dialColor
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

        // 表盘下方地区名截断时悬停显示全文
        ElideTip { anchors.fill: parent }
    }
}