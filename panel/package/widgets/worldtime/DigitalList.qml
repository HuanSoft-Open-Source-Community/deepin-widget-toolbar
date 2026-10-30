// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import "../components" as Components

// 世界时间数字模式的网格视图（从 worldtime 小组件拆分）：
// 标题 + cols×rows 单元格网格（单位数与指针模式一致，纵向双列）。
// 宽格（hostCols≥4）：名左时间右并排；窄格（1×1/2×2）：名上小字、
// 时间下大字上下排列。全部尺寸由可视区减法均分派生、字号钳制不超过
// 单元格——结构性无溢出。表盘少于格子数时留空（与指针模式一致）。
Column {
    id: root

    property var zoneInfos: []
    property var times: []
    // 标题文本由 main.qml 传入：qsTr 上下文随文件名，若在本文件调用会查不到
    // 既有翻译条目（它们登记在 main 上下文下）；空串即隐藏标题（1×1 特例）
    property string titleText: ""
    property int titlePixelSize: 14
    property int cols: 1
    property int rows: 1
    // 窄格（hostCols<4）单元格内改为上下排列
    property bool verticalCells: false
    property int layoutSpacing: 6
    property bool highlightLocal: false
    property real localOffset: 0
    // 整卡互斥与空间采样参考（由 main.qml 注入）：cardConfig=实例配置；
    // textColorValue=未经解析的原始 textColor 配置值（可能含 @flow: 前缀）；
    // cardWidth=卡片宽；cardOffsetX=内容区相对卡片左缘的 x 偏移
    property var cardConfig: null
    property var textColorValue
    property real cardWidth: 0
    property real cardOffsetX: 0
    // 透明模式（由调用方传入 WidgetCard 的 effectiveTransparent/themeTextColor）
    property bool effectiveTransparent: false
    property color themeTextColor: palette.windowText

    anchors.fill: parent
    spacing: root.layoutSpacing

    Text {
        id: titleItem
        visible: root.titleText.length > 0
        text: root.titleText
        font.pixelSize: root.titlePixelSize
        // textColor 为整卡唯一流光 owner 时按自身 x 采样横向彩虹；
        // 透明模式保持主题自适应色分支、不接流光（消费端规则 5）
        color: root.effectiveTransparent ? root.themeTextColor
            : Components.ColorUtils.resolveSiteColor(root.cardConfig, "dials",
                "textColor", root.textColorValue, "#ffffff",
                root.cardOffsetX + titleItem.x + titleItem.width / 2, root.cardWidth)
    }

    Grid {
        id: cellsGrid
        width: root.width
        height: root.height
            - (titleItem.visible ? titleItem.height + root.spacing : 0)
        columns: root.cols
        rows: root.rows
        spacing: root.layoutSpacing

        // 单元格均分可用空间；字号随单元格高度，宽格钳 8..18、窄格上下两档
        property int cellWidth: Math.max(1,
            (width - (root.cols - 1) * spacing) / root.cols)
        property int cellHeight: Math.max(1,
            (height - (root.rows - 1) * spacing) / root.rows)
        property int cityPixelSize: Math.max(8,
            Math.min(18, Math.round(cellHeight * 0.42)))
        property int compactNamePixelSize: Math.max(7,
            Math.min(12, Math.round(cellHeight * 0.26)))
        property int compactTimePixelSize: Math.max(9,
            Math.min(22, Math.round(cellHeight * 0.42)))

        Repeater {
            model: root.zoneInfos.slice(0, root.cols * root.rows)
            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                width: cellsGrid.cellWidth
                height: cellsGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    visible: root.highlightLocal
                        && Math.abs(modelData.offset - root.localOffset) < 0.001
                    color: palette.highlight
                    opacity: 0.16
                }

                // 宽格：地区名（左，elide）+ 时间（右）并排
                Text {
                    id: wideName
                    visible: !root.verticalCells
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width / 2 - 4
                    text: modelData.name
                    font.pixelSize: cellsGrid.cityPixelSize
                    // textColor site 为 owner 时按自身水平中心 x 采样（宽格
                    // 左右两块文字随列位置形成横向彩虹）；透明分支不接流光
                    color: root.effectiveTransparent ? root.themeTextColor
                        : Components.ColorUtils.resolveSiteColor(root.cardConfig,
                            "dials", "textColor", root.textColorValue, "#ffffff",
                            root.cardOffsetX + cell.x + wideName.x
                                + wideName.width / 2, root.cardWidth)
                    opacity: 0.8
                    elide: Text.ElideRight
                    // 地区名截断时悬停显示全文
                    Components.ElideTip { anchors.fill: parent }
                }

                Text {
                    id: wideTime
                    visible: !root.verticalCells
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width / 2 - 4
                    horizontalAlignment: Text.AlignRight
                    text: index < root.times.length ? root.times[index] : "--:--"
                    font.pixelSize: cellsGrid.cityPixelSize
                    color: root.effectiveTransparent ? root.themeTextColor
                        : Components.ColorUtils.resolveSiteColor(root.cardConfig,
                            "dials", "textColor", root.textColorValue, "#ffffff",
                            root.cardOffsetX + cell.x + wideTime.x
                                + wideTime.width / 2, root.cardWidth)
                }

                // 窄格（1×1/2×2）：上下排列——时间居中在上（大）、
                // 地区名居中在下（小），时间为主信息
                Column {
                    visible: root.verticalCells
                    anchors.centerIn: parent
                    width: cellsGrid.cellWidth - 4
                    spacing: 2

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: index < root.times.length ? root.times[index] : "--:--"
                        font.pixelSize: cellsGrid.compactTimePixelSize
                        // 窄格整块文字居中，按单元格中心 x 采样
                        color: root.effectiveTransparent ? root.themeTextColor
                            : Components.ColorUtils.resolveSiteColor(root.cardConfig,
                                "dials", "textColor", root.textColorValue, "#ffffff",
                                root.cardOffsetX + cell.x + cell.width / 2,
                                root.cardWidth)
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        font.pixelSize: cellsGrid.compactNamePixelSize
                        color: root.effectiveTransparent ? root.themeTextColor
                            : Components.ColorUtils.resolveSiteColor(root.cardConfig,
                                "dials", "textColor", root.textColorValue, "#ffffff",
                                root.cardOffsetX + cell.x + cell.width / 2,
                                root.cardWidth)
                        opacity: 0.8
                        elide: Text.ElideRight
                        // 窄格地区名截断时悬停显示全文
                        Components.ElideTip { anchors.fill: parent }
                    }
                }
            }
        }
    }
}
