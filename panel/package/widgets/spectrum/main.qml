// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：频谱面板（默认 4×2，全图形化、零文字）。
// 数据来自宿主单例 AudioVisualizer：默认 sink monitor 回环的 32 带频谱
// （只读数值，采集在宿主独立线程，绝不触碰麦克风等输入源）。
// 缺省背景色淡绿（#C8E6C9）、频谱内容为主题色（highlightColor 随亮/暗
// 主题自适应，可在设置中改为自定义颜色）；跃动幅度 40%–200% 可调。
// 仅实例可见且面板可见时才注册采集需求（setActive），隐藏即停流。
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    instanceId: ""
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#C8E6C9")
    property color barColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.barColor, root.highlightColor)
    property int amplitude: {
        var value = widgetConfig ? Number(widgetConfig.amplitude) : NaN
        if (!isFinite(value) || value <= 0)
            value = 100
        return Math.max(40, Math.min(200, Math.round(value)))
    }
    property bool showPeaks: widgetConfig && widgetConfig.showPeaks !== undefined
        ? widgetConfig.showPeaks : true
    property bool panelVisible: Panel.visible

    // 需要采集的条件：实例可见且面板可见
    readonly property bool captureActive: root.visible && root.panelVisible
    // 空闲判定：采集不可用或整体音量极低（与 onPaint 的 idle 判定一致）。
    // 空闲时重绘降到 ~12fps（呼吸动画），仅在有真实电平变化时回到 30fps，
    // 视觉流畅与资源占用取平衡（扁平矩形快路径下开销仍很小）。
    property bool idleState: true
    // 空闲重绘间隔：1000/12 ≈ 83ms（~12fps）
    readonly property int idleIntervalMs: 83

    function computeIdle() {
        if (!AudioVisualizer.available)
            return true
        var levels = AudioVisualizer.levels
        var bandCount = AudioVisualizer.bandCount
        var peak = 0
        for (var k = 0; k < bandCount; k++) {
            if (levels.length > k && levels[k] > peak)
                peak = levels[k]
        }
        return peak < 3
    }
    // 柱数随宽度自适应（8–48 根）
    readonly property int barCount: Math.max(8,
        Math.min(48, Math.floor((root.width - root.margin * 2) / 12)))
    // 每根柱的峰值（QML 侧独立衰减，避免代理接口膨胀）
    property var barPeaks: []

    // 把 32 带线性插值映射到当前柱数（ter-music 同款映射）
    function bandLevel(levels, bandCount, count, index) {
        if (!levels || levels.length < bandCount || count <= 1)
            return 0
        var normalized = (index * (bandCount - 1)) / (count - 1)
        var left = Math.floor(normalized)
        var right = Math.min(bandCount - 1, left + 1)
        var frac = normalized - left
        var lv = levels[left] !== undefined ? levels[left] : 0
        var rv = levels[right] !== undefined ? levels[right] : 0
        return lv * (1 - frac) + rv * frac
    }

    // 圆角柱（Canvas 兼容性优先：手绘圆弧，不依赖 roundRect）
    function roundedBar(ctx, x, y, w, h, r) {
        if (r > h / 2)
            r = h / 2
        ctx.beginPath()
        ctx.moveTo(x, y + h)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.quadraticCurveTo(x + w, y, x + w, y + r)
        ctx.lineTo(x + w, y + h)
        ctx.closePath()
    }

    function syncCapture() {
        if (root.instanceId.length > 0)
            AudioVisualizer.setActive(root.instanceId, root.captureActive)
    }

    onVisibleChanged: {
        root.syncCapture()
        spectrumCanvas.requestPaint()
    }
    onPanelVisibleChanged: root.syncCapture()
    onInstanceIdChanged: root.syncCapture()
    onBarColorChanged: spectrumCanvas.requestPaint()
    onAmplitudeChanged: spectrumCanvas.requestPaint()
    onShowPeaksChanged: spectrumCanvas.requestPaint()
    onPaletteChanged: spectrumCanvas.requestPaint()
    Component.onCompleted: root.syncCapture()
    Component.onDestruction: {
        if (root.instanceId.length > 0)
            AudioVisualizer.setActive(root.instanceId, false)
    }

    // 空闲呼吸 5fps；levels 变化（播放开始）由 Connections 立即切回 30fps
    Timer {
        interval: root.idleState ? root.idleIntervalMs : 33
        repeat: true
        running: root.captureActive
        onTriggered: spectrumCanvas.requestPaint()
    }

    Connections {
        target: AudioVisualizer
        function onLevelsChanged() {
            var wasIdle = root.idleState
            root.idleState = root.computeIdle()
            if (wasIdle && !root.idleState)
                spectrumCanvas.requestPaint()   // 播放开始：立即重绘
        }
        function onAvailableChanged() {
            root.idleState = root.computeIdle()
            spectrumCanvas.requestPaint()
        }
    }

    Canvas {
        id: spectrumCanvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w <= 2 || h <= 2)
                return
            ctx.clearRect(0, 0, w, h)

            var levels = AudioVisualizer.levels
            var bandCount = AudioVisualizer.bandCount
            var available = AudioVisualizer.available
            var amp = root.amplitude / 100.0
            var n = root.barCount
            var gap = Math.max(1, Math.min(3, Math.round(w * 0.006)))
            var barW = (w - gap * (n - 1)) / n
            if (barW < 1)
                return
            var now = Date.now() / 1000.0

            // 空闲判定：采集不可用或整体音量极低 → 呼吸待机
            var peak = 0
            for (var k = 0; k < bandCount; k++) {
                if (levels.length > k && levels[k] > peak)
                    peak = levels[k]
            }
            var idle = !available || peak < 3

            if (root.barPeaks.length !== n) {
                var fresh = []
                for (var f = 0; f < n; f++)
                    fresh.push(0)
                root.barPeaks = fresh
            }

            var baseY = h - 2
            var maxBarH = h - 4
            var color = root.barColor
            var col = 0

            // 空闲快路径：扁平矩形 + 低速呼吸，跳过渐变/圆角路径（软件渲染大头）。
            // 空闲柱体仅 4%-14% 高度，实色填充观感与渐变几乎一致。
            // ~12fps 空闲重绘下仍保持低成本（仅 fillRect）。
            if (idle) {
                ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.55)
                for (var bi = 0; bi < n; bi++) {
                    var wave = 0.5 + 0.5 * Math.sin(now * 0.6 + bi * 0.45)
                    var bh = Math.max(1, maxBarH * (0.04 + 0.10 * wave))
                    ctx.fillRect(bi * (barW + gap), baseY - bh, barW, bh)
                    root.barPeaks[bi] = 0
                }
                return
            }

            for (var i = 0; i < n; i++) {
                var level = root.bandLevel(levels, bandCount, n, i)
                var scaled = level * amp
                if (scaled > 100)
                    scaled = 100
                var barH = maxBarH * scaled / 100.0
                if (idle) {
                    var wave = 0.5 + 0.5 * Math.sin(now * 1.8 + i * 0.45)
                    barH = maxBarH * (0.04 + 0.10 * wave)
                }
                if (barH < 1)
                    barH = 1

                var x = col * (barW + gap)
                var y = baseY - barH

                // 柱体：底部实色 → 顶部半透明的垂直渐变
                var grad = ctx.createLinearGradient(0, y, 0, baseY)
                grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.45))
                grad.addColorStop(1, color)
                ctx.fillStyle = grad
                root.roundedBar(ctx, x, y, barW, barH, Math.min(4, barW * 0.4))
                ctx.fill()

                // 峰值帽：本柱历史峰值（升立即跟随、降缓慢衰减）
                if (root.showPeaks && !idle) {
                    var prev = root.barPeaks[i]
                    if (scaled > prev)
                        prev = scaled
                    else if (prev > 0)
                        prev -= 1.2
                    if (prev < 0)
                        prev = 0
                    root.barPeaks[i] = prev
                    var capH = maxBarH * prev / 100.0
                    if (capH >= 1) {
                        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.85)
                        ctx.fillRect(x + 1, baseY - capH - 2, barW - 2, 2)
                    }
                } else {
                    root.barPeaks[i] = 0
                }
                col++
            }
        }
    }
}