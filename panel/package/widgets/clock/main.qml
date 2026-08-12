// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 内置示例小组件：数字时钟（默认 2×2）
Item {
    id: root

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font: DTK.fontManager.t2
            color: palette.windowText
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            font: DTK.fontManager.t7
            color: palette.windowText
            opacity: 0.7
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            timeText.text = Qt.formatTime(new Date(), "HH:mm:ss")
            dateText.text = Qt.formatDate(new Date(), Qt.DefaultLocaleLongDate)
        }
    }
}
