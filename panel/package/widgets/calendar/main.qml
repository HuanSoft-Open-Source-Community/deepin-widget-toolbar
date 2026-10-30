// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import "../components" as Components

// 内置示例小组件：当月月历（默认 2×2）
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    // ---- 当月月历数据 ----
    property date current: new Date()
    property int year: current.getFullYear()
    property int month: current.getMonth()   // 0-11
    property int daysInMonth: new Date(year, month + 1, 0).getDate()
    property bool mondayFirst: widgetConfig && widgetConfig.weekStartsOn === "monday"
    property int firstWeekday: {
        var jsDay = new Date(year, month, 1).getDay()
        return root.mondayFirst ? (jsDay + 6) % 7 : jsDay
    }
    property var cells: {
        var list = []
        for (var i = 0; i < firstWeekday; i++)
            list.push(0)
        for (var d = 1; d <= daysInMonth; d++)
            list.push(d)
        while (list.length % 7 !== 0)
            list.push(0)
        return list
    }
    property var weekDays: root.mondayFirst
        ? [qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"),
            qsTr("Fri"), qsTr("Sat"), qsTr("Sun")]
        : [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"),
            qsTr("Thu"), qsTr("Fri"), qsTr("Sat")]
    property bool highlightToday: widgetConfig && widgetConfig.highlightToday !== undefined
        ? widgetConfig.highlightToday : true
    property int gridSpacing: 1
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 取色统一走 ColorUtils Site 入口：整卡唯一 owner 互斥兜底 + 横向空间渐变采样
    //（整宽条带 x 传卡片中心；日期格/星期文字为重复元素，在委托内按列 x 逐格采样）
    backgroundColor: Components.ColorUtils.themedOpaqueSiteColor(
        widgetConfig, "dials", "backgroundColor",
        widgetConfig && widgetConfig.backgroundColor, "#ffffff", "#1f1f1f",
        root.width / 2, root.width)
    textColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "textColor",
        widgetConfig && widgetConfig.textColor, "#222222", "#e8e8e8",
        root.width / 2, root.width)
    property color titleBackgroundColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "titleBackgroundColor",
        widgetConfig && widgetConfig.titleBackgroundColor, "#e64545", "#8c2f2f",
        root.width / 2, root.width)
    property color titleTextColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "titleTextColor",
        widgetConfig && widgetConfig.titleTextColor, "#ffffff", "#f2f2f2",
        root.width / 2, root.width)
    property color weekdayBackgroundColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "weekdayBackgroundColor",
        widgetConfig && widgetConfig.weekdayBackgroundColor, "#ffc0cb", "#3a2a2e",
        root.width / 2, root.width)
    highlightColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "highlightColor",
        widgetConfig && widgetConfig.highlightColor, "#e64545",
        root.width / 2, root.width)
    highlightedTextColor: Components.ColorUtils.resolveSiteColor(
        widgetConfig, "dials", "highlightedTextColor",
        widgetConfig && widgetConfig.highlightedTextColor, "#ffffff",
        root.width / 2, root.width)
    property color gridColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "gridColor",
        widgetConfig && widgetConfig.gridColor, "#cccccc", "#3a3a3a",
        root.width / 2, root.width)
    // 标题文字 site 是否为整卡唯一流光 owner（标题 FlowText 门控）
    readonly property bool titleTextColorIsFlow: Components.ColorUtils.flowSiteIsOwner(
        widgetConfig, "dials", "titleTextColor")
        && Components.ColorUtils.isFlow(widgetConfig && widgetConfig.titleTextColor)
    // 用实数除法让 7 列 + 6px 间距精确填满内容区，
    // 避免 Math.floor 取整后右侧露出网格底色竖线。
    property real cellWidth: Math.max(12,
        (content.width - 6 * root.gridSpacing) / 7)
    // 透明模式下标题/星期条不占位（配色模式前的 42 常量），保证网格仍填满
    property int cellHeight: Math.max(14,
        Math.min(Math.round(cellWidth * 0.85),
            Math.round((content.height - (root.effectiveTransparent ? 42 : 64)) / 6)))
    property int titlePixelSize: Math.max(10, Math.min(24, Math.round(content.width * 0.045)))
    property int weekdayPixelSize: Math.max(8, Math.min(16, Math.round(content.width * 0.032)))
    property int dayPixelSize: Math.max(8, Math.min(18, Math.round(content.width * 0.038)))
    // 网格单元中心相对卡片的 x：内容区左缘（margin）+ 列位置 ×（格宽 + 间距）+ 半格宽。
    // 日期格与星期文字都在委托内按此 x 逐格采样，形成 7 列横向彩虹
    function cellCenterX(index) {
        return root.margin + (index % 7) * (root.cellWidth + root.gridSpacing)
            + root.cellWidth / 2
    }
    // 日期格非高亮底色：与卡片底色同一 Site 入口，但按本列中心 x 采样，
    // 流光 owner 时 7 列各取一段色相形成横向彩虹。非流光/非 owner 时
    // 与 root.backgroundColor（卡片中心采样）返回同一颜色，静态外观不变。
    function cellBackgroundColor(index) {
        return Components.ColorUtils.themedOpaqueSiteColor(
            root.widgetConfig, "dials", "backgroundColor",
            root.widgetConfig && root.widgetConfig.backgroundColor,
            "#ffffff", "#1f1f1f", root.cellCenterX(index), root.width)
    }

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        // 标题条：仅非透明模式显示（配色模式前的透明样式为纯文字）
        Rectangle {
            width: parent.width
            height: root.titlePixelSize + 8
            radius: 4
            visible: !root.effectiveTransparent
            color: root.titleBackgroundColor

            // 标题文字（居中单块）：site 为整卡唯一流光 owner 时启用 FlowText
            // 段内彩虹；非 owner / 静态色走普通 color 渲染，零额外开销
            Components.FlowText {
                anchors.centerIn: parent
                text: Qt.formatDate(root.current, qsTr("yyyy MMMM"))
                font.pixelSize: root.titlePixelSize
                color: root.titleTextColor
                flowGradient: root.titleTextColorIsFlow
                flowBaseColor: Components.ColorUtils.flowBase(
                    root.widgetConfig && root.widgetConfig.titleTextColor, "#ffffff")
                // 相位读取按 owner 门控：非流光路径不注册 flowPhase 依赖（性能红线）
                flowPhaseValue: flowGradient ? Components.ColorUtils.flowPhase : 0
                flowDark: Components.ColorUtils.dark
                // 居中单块：左缘卡片x = 内容区左缘(margin) + (内容区宽 - 文本宽)/2
                flowOffset: Components.ColorUtils.spaceOffset(
                    root.margin + (parent.width - implicitWidth) / 2, root.width)
                flowSpan: Components.ColorUtils.spaceOffset(implicitWidth, root.width)
            }
        }

        // 透明模式标题：配色模式前样式——无底色条，主题自适应文字
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.effectiveTransparent
            text: Qt.formatDate(root.current, qsTr("yyyy MMMM"))
            font.pixelSize: root.titlePixelSize
            color: root.themeTextColor
        }

        // 星期条：仅非透明模式显示
        Rectangle {
            width: parent.width
            height: root.weekdayPixelSize + 6
            radius: 4
            visible: !root.effectiveTransparent
            color: root.weekdayBackgroundColor

            Row {
                width: parent.width
                spacing: root.gridSpacing
                Repeater {
                    model: root.weekDays
                    delegate: Text {
                        width: root.cellWidth
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: root.weekdayPixelSize
                        // 7 列重复文字按列 x 采样，与日期格同一横向彩虹口径
                        color: Components.ColorUtils.themedSiteColor(
                            root.widgetConfig, "dials", "weekdayTextColor",
                            root.widgetConfig && root.widgetConfig.weekdayTextColor,
                            "#8a3a3a", "#e2a7af", root.cellCenterX(index), root.width)
                    }
                }
            }
        }

        // 透明模式星期行：配色模式前样式——无底色条，半透明主题文字
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.effectiveTransparent
            spacing: root.gridSpacing
            Repeater {
                model: root.weekDays
                delegate: Text {
                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: root.weekdayPixelSize
                    color: root.themeTextColor
                    opacity: 0.6
                }
            }
        }

        Item {
            width: content.width
            height: Math.ceil(root.cells.length / 7) * root.cellHeight
                + (Math.ceil(root.cells.length / 7) - 1) * root.gridSpacing

            // 灰色网格底色：Grid 用 1px 间距透出，形成网格线；透明模式不画
            Rectangle {
                anchors.fill: parent
                radius: 4
                visible: !root.effectiveTransparent
                color: root.gridColor
            }

            Grid {
                anchors.fill: parent
                columns: 7
                spacing: root.gridSpacing
                Repeater {
                    model: root.cells
                    delegate: Rectangle {
                        width: root.cellWidth
                        height: root.cellHeight
                        // 今日高亮底按列 x 逐格采样（7 列横向彩虹）；透明模式保持透出
                        color: root.highlightToday
                            && modelData === root.current.getDate()
                            && root.month === root.current.getMonth()
                            ? Components.ColorUtils.resolveSiteColor(
                                root.widgetConfig, "dials", "highlightColor",
                                root.widgetConfig && root.widgetConfig.highlightColor,
                                "#e64545", root.cellCenterX(index), root.width)
                            : (root.effectiveTransparent
                                ? "transparent" : root.cellBackgroundColor(index))

                        Text {
                            anchors.centerIn: parent
                            text: modelData > 0 ? modelData : ""
                            font.pixelSize: root.dayPixelSize
                            // 日期文字按列 x 逐格采样；透明模式主题色分支不接流光
                            color: root.highlightToday
                                && modelData === root.current.getDate()
                                && root.month === root.current.getMonth()
                                ? Components.ColorUtils.resolveSiteColor(
                                    root.widgetConfig, "dials", "highlightedTextColor",
                                    root.widgetConfig && root.widgetConfig.highlightedTextColor,
                                    "#ffffff", root.cellCenterX(index), root.width)
                                : (root.effectiveTransparent ? root.themeTextColor
                                    : Components.ColorUtils.themedSiteColor(
                                        root.widgetConfig, "dials", "textColor",
                                        root.widgetConfig && root.widgetConfig.textColor,
                                        "#222222", "#e8e8e8",
                                        root.cellCenterX(index), root.width))
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.current = new Date()
        }
    }
}
