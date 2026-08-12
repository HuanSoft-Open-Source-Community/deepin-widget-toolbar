// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 内置示例小组件：当月月历（默认 2×2）
Item {
    id: root

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    // ---- 当月月历数据 ----
    property date current: new Date()
    property int year: current.getFullYear()
    property int month: current.getMonth()   // 0-11
    property int daysInMonth: new Date(year, month + 1, 0).getDate()
    // 当月 1 号的星期（0=周日）
    property int firstWeekday: new Date(year, month, 1).getDay()
    // 生成 42 格（6 行 × 7 列），前置空白
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
    property var weekDays: [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")]

    Column {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // 标题：2025 年 8 月
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.current, qsTr("yyyy MMMM"))
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        // 星期表头
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Repeater {
                model: root.weekDays
                delegate: Text {
                    width: root.width / 7 - 2
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font: DTK.fontManager.t7
                    color: palette.windowText
                    opacity: 0.6
                }
            }
        }

        // 日期网格
        Grid {
            columns: 7
            spacing: 2
            Repeater {
                model: root.cells
                delegate: Rectangle {
                    width: root.width / 7 - 2
                    height: width * 0.8
                    radius: 4
                    color: modelData === root.current.getDate() && root.month === root.current.getMonth()
                        ? palette.highlight : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData > 0 ? modelData : ""
                        font: DTK.fontManager.t7
                        color: modelData === root.current.getDate() && root.month === root.current.getMonth()
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
            // 跨天时刷新月历
            root.current = new Date()
        }
    }
}
