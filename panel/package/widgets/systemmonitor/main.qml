// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 内置示例小组件：系统资源监视（默认 2×2）
// 数据来自宿主单例 SystemInfo（/proc/stat、/proc/meminfo、根分区）
Item {
    id: root

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            text: qsTr("System Monitor")
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        // CPU
        Row {
            width: parent.width
            spacing: 8
            Text {
                width: 48
                text: qsTr("CPU")
                font: DTK.fontManager.t7
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                width: parent.width - 48 - 40
                height: 8
                from: 0
                to: 1
                value: SystemInfo.cpuUsage
            }
            Text {
                width: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.cpuUsage * 100) + "%"
                font: DTK.fontManager.t7
                color: palette.windowText
            }
        }

        // 内存
        Row {
            width: parent.width
            spacing: 8
            Text {
                width: 48
                text: qsTr("MEM")
                font: DTK.fontManager.t7
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                width: parent.width - 48 - 40
                height: 8
                from: 0
                to: 1
                value: SystemInfo.memUsedPercent
            }
            Text {
                width: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.memUsedPercent * 100) + "%"
                font: DTK.fontManager.t7
                color: palette.windowText
            }
        }

        // 磁盘
        Row {
            width: parent.width
            spacing: 8
            Text {
                width: 48
                text: qsTr("DISK")
                font: DTK.fontManager.t7
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                width: parent.width - 48 - 40
                height: 8
                from: 0
                to: 1
                value: SystemInfo.diskUsedPercent
            }
            Text {
                width: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.diskUsedPercent * 100) + "%"
                font: DTK.fontManager.t7
                color: palette.windowText
            }
        }
    }
}
