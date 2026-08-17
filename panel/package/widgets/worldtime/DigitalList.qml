// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 世界时间数字模式的列表视图（从 worldtime 小组件拆分）：
// 标题 + 时区名/时间行，本机时区行带淡色高亮框。
Column {
    id: root

    property var zoneInfos: []
    property var times: []
    property int layoutSpacing: 6
    property int rowHeight: 20
    property int titlePixelSize: 14
    property int cityPixelSize: 12
    property bool highlightLocal: false
    property real localOffset: 0
    property color textColor: palette.windowText
    // 透明模式（由调用方传入 WidgetCard 的 effectiveTransparent/themeTextColor）
    property bool effectiveTransparent: false
    property color themeTextColor: palette.windowText

    visible: zoneInfos.length > 0
    anchors.fill: parent
    spacing: root.layoutSpacing

    Text {
        text: qsTr("World Time")
        font.pixelSize: root.titlePixelSize
        color: root.effectiveTransparent ? root.themeTextColor : root.textColor
    }

    Repeater {
        model: root.zoneInfos
        delegate: Item {
            required property var modelData
            required property int index

            width: root.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                radius: 4
                visible: root.highlightLocal
                    && Math.abs(modelData.offset - root.localOffset) < 0.001
                color: palette.highlight
                opacity: 0.16
            }

            Text {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: root.width / 2 - 4
                text: modelData.name
                font.pixelSize: root.cityPixelSize
                color: root.effectiveTransparent ? root.themeTextColor : root.textColor
                opacity: 0.8
                elide: Text.ElideRight
            }

            Text {
                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                width: root.width / 2 - 4
                horizontalAlignment: Text.AlignRight
                text: index < root.times.length ? root.times[index] : "--:--"
                font.pixelSize: root.cityPixelSize
                color: root.effectiveTransparent ? root.themeTextColor : root.textColor
            }
        }
    }
}
