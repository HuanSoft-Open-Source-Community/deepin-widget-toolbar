// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 内置示例小组件：世界时间（默认 2×2）
Item {
    id: root

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    // 城市：名称 + UTC 偏移（小时）
    property var cities: [
        { "name": qsTr("Beijing"), "offset": 8 },
        { "name": qsTr("Tokyo"), "offset": 9 },
        { "name": qsTr("London"), "offset": 0 },
        { "name": qsTr("New York"), "offset": -5 }
    ]

    // 各城市当前时间文本（由 Timer 周期性刷新）
    property var times: []

    function cityTime(offset) {
        var now = new Date()
        // 本地 UTC 偏移（分钟），换算到目标时区
        var utcMs = now.getTime() + now.getTimezoneOffset() * 60000
        return new Date(utcMs + offset * 3600000)
    }

    function updateTimes() {
        var t = []
        for (var i = 0; i < root.cities.length; i++)
            t.push(Qt.formatTime(root.cityTime(root.cities[i].offset), "HH:mm"))
        root.times = t
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Text {
            text: qsTr("World Time")
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        Repeater {
            model: root.cities
            delegate: Row {
                width: parent.width
                spacing: 8
                Text {
                    width: parent.width / 2
                    text: modelData.name
                    font: DTK.fontManager.t7
                    color: palette.windowText
                    opacity: 0.8
                }

                Text {
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                    text: index < root.times.length ? root.times[index] : "--:--"
                    font: DTK.fontManager.t7
                    color: palette.windowText
                }
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateTimes()
    }
}
