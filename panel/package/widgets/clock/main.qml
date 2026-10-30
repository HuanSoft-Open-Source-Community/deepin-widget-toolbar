// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置示例小组件：数字/指针双模式时钟（默认指针、2×2）
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    property bool analogMode: widgetConfig && widgetConfig.clockMode === "analog"
    property bool preloadTime: widgetConfig && widgetConfig.preloadTime !== undefined
        ? widgetConfig.preloadTime : true
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 取色统一走 ColorUtils Site 入口：整卡唯一 owner 互斥兜底 +
    // 横向空间渐变采样（本卡元素均居中，x 传卡片中心 width/2，
    // offset 恒定、随整卡共享相位跑马）
    backgroundColor: Components.ColorUtils.opaqueSiteColor(
        widgetConfig, "dials", "backgroundColor",
        widgetConfig && widgetConfig.backgroundColor, "#000000",
        root.width / 2, root.width)
    textColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "textColor",
        widgetConfig && widgetConfig.textColor, "#ffffff",
        root.width / 2, root.width)
    // textColor 为整卡唯一流光 owner：数字模式时间/日期文字启用 FlowText
    // 段内彩虹（owner 判定统一入口，见 spec「消费端接线规则」3）
    readonly property bool textColorIsFlow: Components.ColorUtils.flowSiteIsOwner(
        widgetConfig, "dials", "textColor")
        && Components.ColorUtils.isFlow(widgetConfig && widgetConfig.textColor)
    // 表盘 Canvas 用色走低频相位（约 7.5fps），避免整块画布按 15fps 无谓重绘；
    // owner 流光时盘内刻度/底色由 AnalogClock 按 flowMeta 原始 base 逐图元采样，
    // 这里注入的解析色仅作为非 owner 单色与低频重绘驱动
    property color dialBackgroundColor: Components.ColorUtils.canvasSiteColor(
        widgetConfig, "dials", "dialBackgroundColor",
        widgetConfig && widgetConfig.dialBackgroundColor, "#ffffff",
        root.width / 2, root.width)
    property color dialColor: Components.ColorUtils.canvasSiteColor(
        widgetConfig, "dials", "dialColor",
        widgetConfig && widgetConfig.dialColor, "#000000",
        root.width / 2, root.width)
    // 指针是场景图矩形，可跟随 15fps 主相位；owner 门控取色，
    // 非 owner 的 @flow: 由 Site 入口回退浅色缺省（不再手工错峰 offset）
    property color hourMinuteHandColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "hourMinuteHandColor",
        widgetConfig && widgetConfig.hourMinuteHandColor, "#000000",
        root.width / 2, root.width)
    property color secondHandColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "secondHandColor",
        widgetConfig && widgetConfig.secondHandColor, "#ff4d4f",
        root.width / 2, root.width)
    highlightColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "highlightColor",
        widgetConfig && widgetConfig.highlightColor, "#4d8cff",
        root.width / 2, root.width)
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

        // 数字时间/日期：textColor site 为整卡唯一 owner 时启用 FlowText
        // 段内彩虹；透明模式分支保持主题自适应色、不接流光（消费端规则 5）
        Components.FlowText {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: root.timePixelSize
            color: root.effectiveTransparent ? root.themeTextColor : palette.windowText
            flowGradient: root.textColorIsFlow && !root.effectiveTransparent
            flowBaseColor: Components.ColorUtils.flowBase(
                root.widgetConfig && root.widgetConfig.textColor, "#ffffff")
            // 相位读取按 owner 门控：非流光路径不注册 flowPhase 依赖（性能红线）
            flowPhaseValue: flowGradient ? Components.ColorUtils.flowPhase : 0
            flowDark: Components.ColorUtils.dark
            // 左缘/宽度换算卡片坐标口径：Column 居中于内容容器，
            // 左缘卡片x = margin + (内容宽 - 自身隐式宽)/2
            flowOffset: Components.ColorUtils.spaceOffset(
                root.margin + (root.contentWidth - implicitWidth) / 2, root.width)
            flowSpan: Components.ColorUtils.spaceOffset(implicitWidth, root.width)
        }

        Components.FlowText {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.compact
            font.pixelSize: root.datePixelSize
            color: root.effectiveTransparent ? root.themeTextColor : palette.windowText
            opacity: 0.7
            flowGradient: root.textColorIsFlow && !root.effectiveTransparent
            flowBaseColor: Components.ColorUtils.flowBase(
                root.widgetConfig && root.widgetConfig.textColor, "#ffffff")
            // 相位读取按 owner 门控：非流光路径不注册 flowPhase 依赖（性能红线）
            flowPhaseValue: flowGradient ? Components.ColorUtils.flowPhase : 0
            flowDark: Components.ColorUtils.dark
            flowOffset: Components.ColorUtils.spaceOffset(
                root.margin + (root.contentWidth - implicitWidth) / 2, root.width)
            flowSpan: Components.ColorUtils.spaceOffset(implicitWidth, root.width)
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
        // 流光逐图元采样：面/刻度 site 为 owner 时置 owner=true 并传原始
        // base 色，由 AnalogClock 在 Canvas 内按各刻度自身 x 描彩虹
        flowMeta: ({
            face: {
                owner: Components.ColorUtils.flowSiteIsOwner(
                        root.widgetConfig, "dials", "dialBackgroundColor")
                    && Components.ColorUtils.isFlow(
                        root.widgetConfig && root.widgetConfig.dialBackgroundColor),
                base: Components.ColorUtils.flowBase(
                    root.widgetConfig && root.widgetConfig.dialBackgroundColor, "#ffffff")
            },
            dial: {
                owner: Components.ColorUtils.flowSiteIsOwner(
                        root.widgetConfig, "dials", "dialColor")
                    && Components.ColorUtils.isFlow(
                        root.widgetConfig && root.widgetConfig.dialColor),
                base: Components.ColorUtils.flowBase(
                    root.widgetConfig && root.widgetConfig.dialColor, "#000000")
            }
        })
        // 空间参考：表盘居中于内容容器，中心卡片x = margin + 内容宽/2
        flowWidthRef: root.width
        flowCenterX: root.margin + root.contentWidth / 2
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
