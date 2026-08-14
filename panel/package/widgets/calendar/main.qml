// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import "../components" as Components

// 内置示例小组件：当月月历（默认 2×2）
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
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
    property int cellWidth: Math.max(12, Math.floor((content.width - 6 * 2) / 7))
    property int cellHeight: Math.max(14,
        Math.min(Math.round(cellWidth * 0.85), Math.round((content.height - 42) / 6)))
    property int titlePixelSize: Math.max(10, Math.min(24, Math.round(content.width * 0.045)))
    property int weekdayPixelSize: Math.max(8, Math.min(16, Math.round(content.width * 0.032)))
    property int dayPixelSize: Math.max(8, Math.min(18, Math.round(content.width * 0.038)))

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.current, qsTr("yyyy MMMM"))
            font.pixelSize: root.titlePixelSize
            color: palette.windowText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Repeater {
                model: root.weekDays
                delegate: Text {
                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: root.weekdayPixelSize
                    color: palette.windowText
                    opacity: 0.6
                }
            }
        }

        Grid {
            width: content.width
            columns: 7
            spacing: 2
            Repeater {
                model: root.cells
                delegate: Rectangle {
                    width: root.cellWidth
                    height: root.cellHeight
                    radius: 4
                    color: root.highlightToday && modelData === root.current.getDate()
                        && root.month === root.current.getMonth()
                        ? palette.highlight : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData > 0 ? modelData : ""
                        font.pixelSize: root.dayPixelSize
                        color: root.highlightToday && modelData === root.current.getDate()
                            && root.month === root.current.getMonth()
                            ? palette.highlightedText : palette.windowText
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
