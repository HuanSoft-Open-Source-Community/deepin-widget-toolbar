// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置示例小组件：系统资源监视（默认 2×2）
// CPU / 内存 / 磁盘 IO / GPU / NPU 数据来自宿主单例 SystemInfo。
// 每实例可配置指标行显隐与刷新间隔；SystemInfo 为全局单例，
// 多个实例同时存在时以最后加载/修改的刷新间隔为准。
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
    property bool showCpu: widgetConfig && widgetConfig.showCpu !== undefined
        ? widgetConfig.showCpu : true
    property bool showMem: widgetConfig && widgetConfig.showMem !== undefined
        ? widgetConfig.showMem : true
    property bool showDisk: widgetConfig && widgetConfig.showDisk !== undefined
        ? widgetConfig.showDisk : true
    property bool showGpu: widgetConfig && widgetConfig.showGpu !== undefined
        ? widgetConfig.showGpu : true
    property bool showNpu: widgetConfig && widgetConfig.showNpu !== undefined
        ? widgetConfig.showNpu : true
    property int refreshInterval: widgetConfig && widgetConfig.refreshInterval
        ? Number(widgetConfig.refreshInterval) : 1000
    property int titlePixelSize: Math.max(10, Math.min(20, Math.round(content.height * 0.075)))
    property int labelPixelSize: Math.max(7, Math.min(13, Math.round(content.height * 0.045)))
    property int barHeight: Math.max(5, Math.min(12, Math.round(content.height * 0.035)))

    function applyRefreshInterval() {
        SystemInfo.setRefreshInterval(root.refreshInterval)
    }

    onWidgetConfigChanged: applyRefreshInterval()
    Component.onCompleted: applyRefreshInterval()

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Math.max(3, content.height * 0.018)

        Text {
            Layout.fillWidth: true
            text: qsTr("System Monitor")
            font.pixelSize: root.titlePixelSize
            color: palette.windowText
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showCpu
            spacing: 8

            Text {
                Layout.preferredWidth: 48
                text: qsTr("CPU")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                Layout.fillWidth: true
                height: root.barHeight
                from: 0
                to: 1
                value: SystemInfo.cpuUsage
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.cpuUsage * 100) + "%"
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showMem
            spacing: 8

            Text {
                Layout.preferredWidth: 48
                text: qsTr("MEM")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                Layout.fillWidth: true
                height: root.barHeight
                from: 0
                to: 1
                value: SystemInfo.memUsedPercent
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.memUsedPercent * 100) + "%"
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showDisk
            spacing: 8

            Text {
                Layout.preferredWidth: 48
                text: qsTr("DISK")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                Layout.fillWidth: true
                height: root.barHeight
                from: 0
                to: 1
                value: SystemInfo.diskBusyPercent
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(SystemInfo.diskBusyPercent * 100) + "%"
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showGpu
            spacing: 8

            Text {
                Layout.preferredWidth: 48
                text: qsTr("GPU")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                Layout.fillWidth: true
                height: root.barHeight
                from: 0
                to: 1
                value: SystemInfo.gpuAvailable ? SystemInfo.gpuUsage : 0
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: SystemInfo.gpuAvailable
                    ? Math.round(SystemInfo.gpuUsage * 100) + "%" : qsTr("N/A")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: SystemInfo.gpuAvailable ? 1.0 : 0.5
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showNpu
            spacing: 8

            Text {
                Layout.preferredWidth: 48
                text: qsTr("NPU")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: 0.7
            }
            ProgressBar {
                Layout.fillWidth: true
                height: root.barHeight
                from: 0
                to: 1
                value: SystemInfo.npuAvailable ? SystemInfo.npuUsage : 0
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: SystemInfo.npuAvailable
                    ? Math.round(SystemInfo.npuUsage * 100) + "%" : qsTr("N/A")
                font.pixelSize: root.labelPixelSize
                color: palette.windowText
                opacity: SystemInfo.npuAvailable ? 1.0 : 0.5
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.showCpu && !root.showMem && !root.showDisk
                && !root.showGpu && !root.showNpu
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No metrics enabled")
            font.pixelSize: root.titlePixelSize
            color: palette.windowText
            opacity: 0.6
        }
    }
}
