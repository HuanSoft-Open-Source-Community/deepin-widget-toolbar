// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：系统资源监视（默认 2×2）
// CPU / 内存 / 磁盘 IO / GPU / NPU 数据来自宿主单例 SystemInfo。
// 中号（2×2）固定单列；宽（4×2）与大（4×4）支持双列（默认启用）。
// 所有尺寸都可展示全部已启用指标，单列时压缩行距/行高避免超出格子。
// 渲染使用轻量 Rectangle 进度条，避免 DTK ProgressBar 的持续动画和图层开销。
Components.WidgetCard {
    id: root

    property string instanceId: ""
    property int hostCols: 2
    property int hostRows: 2
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
        ? Math.max(1000, Number(widgetConfig.refreshInterval)) : 5000

    // 双列对宽（4×2）与大（4×4）生效；中号（2×2）固定单列。
    property bool dualColumn: hostCols >= 4
        && (widgetConfig && widgetConfig.dualColumn !== undefined
            ? widgetConfig.dualColumn : true)
    property bool panelVisible: Panel.visible
    property bool monitoringPending: false
    property var metrics: []

    property int metricLabelWidth: 44
    property int metricValueWidth: 42
    property int metricSpacing: dualColumn ? 6 : (root.metrics.length > 4 ? 4 : 8)
    property int barHeight: 6

    function metricDescriptors() {
        return [
            { "id": "cpu", "label": qsTr("CPU") },
            { "id": "mem", "label": qsTr("MEM") },
            { "id": "disk", "label": qsTr("DISK") },
            { "id": "gpu", "label": qsTr("GPU") },
            { "id": "npu", "label": qsTr("NPU") }
        ]
    }

    function metricEnabled(metricId) {
        switch (metricId) {
            case "cpu": return root.showCpu
            case "mem": return root.showMem
            case "disk": return root.showDisk
            case "gpu": return root.showGpu
            case "npu": return root.showNpu
        }
        return false
    }

    function metricAvailable(metricId) {
        if (metricId === "gpu")
            return SystemInfo.gpuAvailable
        if (metricId === "npu")
            return SystemInfo.npuAvailable
        return true
    }

    function metricUsage(metricId) {
        switch (metricId) {
            case "cpu": return SystemInfo.cpuUsage
            case "mem": return SystemInfo.memUsedPercent
            case "disk": return SystemInfo.diskBusyPercent
            case "gpu": return SystemInfo.gpuAvailable ? SystemInfo.gpuUsage : 0
            case "npu": return SystemInfo.npuAvailable ? SystemInfo.npuUsage : 0
        }
        return 0
    }

    function metricText(metricId) {
        if (metricId === "gpu" && !SystemInfo.gpuAvailable)
            return qsTr("N/A")
        if (metricId === "npu" && !SystemInfo.npuAvailable)
            return qsTr("N/A")
        return Math.round(root.metricUsage(metricId) * 100) + "%"
    }

    function visibleMetrics() {
        var descriptors = root.metricDescriptors()
        var result = []
        // 全部指标最多 5 项；中号单列时由布局压缩行距/行高，保证不超出格子。
        for (var i = 0; i < descriptors.length; ++i) {
            if (root.metricEnabled(descriptors[i].id))
                result.push(descriptors[i])
        }
        return result
    }

    function monitoredMetricIds() {
        var ids = []
        for (var i = 0; i < root.metrics.length; ++i)
            ids.push(root.metrics[i].id)
        return ids
    }

    function applyMonitoringState() {
        root.monitoringPending = false
        root.metrics = root.visibleMetrics()

        if (root.instanceId.length === 0)
            return

        var ids = root.monitoredMetricIds()
        var active = root.visible && root.panelVisible && ids.length > 0
        SystemInfo.updateMonitor(root.instanceId, active, ids, root.refreshInterval)
    }

    function scheduleMonitoringUpdate() {
        if (root.monitoringPending)
            return
        root.monitoringPending = true
        Qt.callLater(function () { root.applyMonitoringState() })
    }

    onWidgetConfigChanged: root.scheduleMonitoringUpdate()
    onVisibleChanged: root.scheduleMonitoringUpdate()
    onPanelVisibleChanged: root.scheduleMonitoringUpdate()
    onHostColsChanged: root.scheduleMonitoringUpdate()
    onHostRowsChanged: root.scheduleMonitoringUpdate()
    onInstanceIdChanged: root.scheduleMonitoringUpdate()
    Component.onCompleted: root.scheduleMonitoringUpdate()
    Component.onDestruction: {
        if (root.instanceId.length > 0)
            SystemInfo.releaseMonitor(root.instanceId)
    }

    component MetricBar: Item {
        required property string metricId
        required property string label

        Text {
            id: labelText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.metricLabelWidth
            text: label
            font: DTK.fontManager.t7
            color: palette.windowText
            opacity: 0.7
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.metricValueWidth
            horizontalAlignment: Text.AlignRight
            text: root.metricText(metricId)
            font: DTK.fontManager.t7
            color: palette.windowText
            opacity: root.metricAvailable(metricId) ? 1.0 : 0.5
        }

        Item {
            id: barTrack
            anchors.left: labelText.right
            anchors.right: valueText.left
            anchors.leftMargin: root.metricSpacing
            anchors.rightMargin: root.metricSpacing
            anchors.verticalCenter: parent.verticalCenter
            height: root.barHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: root.barHeight / 2
                color: palette.windowText
                opacity: 0.15
            }

            Rectangle {
                id: barFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * root.metricUsage(metricId))
                radius: root.barHeight / 2
                color: palette.highlight
            }
        }
    }

    Column {
        id: content
        anchors.fill: parent
        spacing: 6
        clip: true

        Text {
            id: titleText
            width: parent.width
            text: qsTr("System Monitor")
            font: root.hostRows >= 4 ? DTK.fontManager.t5 : DTK.fontManager.t6
            color: palette.windowText
            elide: Text.ElideRight
        }

        Grid {
            id: metricsGrid
            width: parent.width
            height: Math.max(0, content.height - titleText.height - content.spacing)
            columns: root.dualColumn ? 2 : 1
            spacing: root.metricSpacing
            visible: root.metrics.length > 0

            Repeater {
                model: root.metrics
                delegate: MetricBar {
                    required property var modelData

                    metricId: modelData.id
                    label: modelData.label
                    width: metricsGrid.columns > 1
                        ? (metricsGrid.width - metricsGrid.spacing) / 2
                        : metricsGrid.width
                    height: {
                        var rows = Math.max(1,
                            Math.ceil(root.metrics.length / metricsGrid.columns))
                        var compactRows = !root.dualColumn && root.metrics.length > 4
                        var minHeight = compactRows ? 20 : 24
                        return Math.max(minHeight,
                            (metricsGrid.height - metricsGrid.spacing * (rows - 1)) / rows)
                    }
                }
            }
        }

        Text {
            width: parent.width
            height: metricsGrid.height
            visible: root.metrics.length === 0
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No metrics enabled")
            font: root.hostRows >= 4 ? DTK.fontManager.t5 : DTK.fontManager.t6
            color: palette.windowText
            opacity: 0.6
        }
    }
}
