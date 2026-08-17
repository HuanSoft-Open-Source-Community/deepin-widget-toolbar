// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../components" as Components

// 世界时间指针模式的表盘网格视图（从 worldtime 小组件拆分）：
// 随 hostCols/hostRows 网格排布 AnalogClock，属性由调用方注入。
Grid {
    id: root

    property var zoneInfos: []
    property int hostCols: 2
    property int hostRows: 2
    property bool showLabels: true
    property bool highlightLocal: false
    property real localOffset: 0
    property color highlightColor: palette.highlight
    property color textColor: palette.windowText
    // 透明模式（由调用方传入 WidgetCard 的 effectiveTransparent/themeTextColor）
    property bool effectiveTransparent: false
    property color themeTextColor: palette.windowText
    property bool preloadTime: true
    property bool active: false

    visible: zoneInfos.length > 0
    anchors.fill: parent
    columns: root.hostCols
    rows: root.hostRows
    spacing: 2

    Repeater {
        model: root.zoneInfos.slice(0, root.hostCols * root.hostRows)
        delegate: Item {
            required property var modelData

            width: Math.max(1,
                (root.width - (root.hostCols - 1) * root.spacing) / root.hostCols)
            height: Math.max(1,
                (root.height - (root.hostRows - 1) * root.spacing) / root.hostRows)

            Components.AnalogClock {
                anchors.fill: parent
                utcOffset: modelData.offset
                label: modelData.name
                showLabels: root.showLabels
                highlighted: root.highlightLocal
                    && Math.abs(modelData.offset - root.localOffset) < 0.001
                accentColor: root.highlightColor
                faceBackgroundColor: modelData.dialBackground
                // 透明模式下不绘制表盘底色（配色模式前样式）
                transparentFace: root.effectiveTransparent
                dialColor: modelData.dialColor
                hourMinuteHandColor: modelData.hourMinuteColor
                secondHandColor: modelData.secondColor
                // 表盘标签：透明模式用主题自适应文字色（默认 #ffffff 是为黑底设计的）
                textColor: root.effectiveTransparent ? root.themeTextColor : root.textColor
                preloadTime: root.preloadTime
                active: root.active
            }
        }
    }
}
