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
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#ffffff")
    textColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.textColor, "#222222")
    property color titleBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.titleBackgroundColor, "#e64545")
    property color titleTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.titleTextColor, "#ffffff")
    property color weekdayBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.weekdayBackgroundColor, "#ffc0cb")
    property color weekdayTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.weekdayTextColor, "#8a3a3a")
    highlightColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.highlightColor, "#e64545")
    highlightedTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.highlightedTextColor, "#ffffff")
    property color gridColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.gridColor, "#cccccc")
    // 用实数除法让 7 列 + 6px 间距精确填满内容区，
    // 避免 Math.floor 取整后右侧露出网格底色竖线。
    property real cellWidth: Math.max(12,
        (content.width - 6 * root.gridSpacing) / 7)
    property int cellHeight: Math.max(14,
        Math.min(Math.round(cellWidth * 0.85), Math.round((content.height - 64) / 6)))
    property int titlePixelSize: Math.max(10, Math.min(24, Math.round(content.width * 0.045)))
    property int weekdayPixelSize: Math.max(8, Math.min(16, Math.round(content.width * 0.032)))
    property int dayPixelSize: Math.max(8, Math.min(18, Math.round(content.width * 0.038)))

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        Rectangle {
            width: parent.width
            height: root.titlePixelSize + 8
            radius: 4
            color: root.transparentBackground ? "transparent" : root.titleBackgroundColor

            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(root.current, qsTr("yyyy MMMM"))
                font.pixelSize: root.titlePixelSize
                color: root.titleTextColor
            }
        }

        Rectangle {
            width: parent.width
            height: root.weekdayPixelSize + 6
            radius: 4
            color: root.transparentBackground ? "transparent" : root.weekdayBackgroundColor

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
                        color: root.weekdayTextColor
                    }
                }
            }
        }

        Item {
            width: content.width
            height: Math.ceil(root.cells.length / 7) * root.cellHeight
                + (Math.ceil(root.cells.length / 7) - 1) * root.gridSpacing

            // 灰色网格底色：Grid 用 1px 间距透出，形成网格线
            Rectangle {
                anchors.fill: parent
                radius: 4
                color: root.transparentBackground ? "transparent" : root.gridColor
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
                        color: root.transparentBackground ? "transparent"
                            : (root.highlightToday
                                && modelData === root.current.getDate()
                                && root.month === root.current.getMonth()
                                ? root.highlightColor : root.backgroundColor)

                        Text {
                            anchors.centerIn: parent
                            text: modelData > 0 ? modelData : ""
                            font.pixelSize: root.dayPixelSize
                            color: root.highlightToday
                                && modelData === root.current.getDate()
                                && root.month === root.current.getMonth()
                                ? root.highlightedTextColor : root.textColor
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
