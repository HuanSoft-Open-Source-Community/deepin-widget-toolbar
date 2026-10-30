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

    instanceId: ""
    hostCols: 2
    hostRows: 2
    widgetConfig: ({})
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
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 取色统一走 ColorUtils Site 入口：整卡唯一 owner 互斥兜底 + 横向空间
    // 渐变采样（背景/标题/空态提示为整卡级元素，x 传卡片中心 width/2）
    backgroundColor: Components.ColorUtils.themedOpaqueSiteColor(
        widgetConfig, "dials", "backgroundColor",
        widgetConfig && widgetConfig.backgroundColor, "#ff8b5cf6", "#ff3a2f56",
        root.width / 2, root.width)
    // 透明模式（实例透明开关或面板级卡片透明模式）下文字切主题自适应色，
    // 与 clock/calendar/todo/worldtime 保持一致；该分支不接入流光采样。
    // 指标行内标签/数值/进度条色不在此处取值，由 MetricBar 按各行自身 x 采样。
    textColor: root.effectiveTransparent
        ? root.themeTextColor
        : Components.ColorUtils.resolveSiteColor(
            widgetConfig, "dials", "textColor",
            widgetConfig && widgetConfig.textColor, "#ffffff",
            root.width / 2, root.width)
    property color titleTextColor: root.effectiveTransparent
        ? root.themeTextColor
        : Components.ColorUtils.resolveSiteColor(
            widgetConfig, "dials", "titleTextColor",
            widgetConfig && widgetConfig.titleTextColor, "#ffffff",
            root.width / 2, root.width)

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

        // 本行相对卡片左缘的几何（内容容器距卡片 margin，网格内 x 为容器坐标）：
        // 行左缘/行宽与轨道区左缘/宽度，供流光逐行按自身 x 采样（横向彩虹）
        readonly property real rowCardX: root.margin + x
        readonly property real rowWidth: width
        readonly property real trackCardX: rowCardX + root.metricLabelWidth
            + root.metricSpacing
        readonly property real trackWidth: Math.max(0,
            rowWidth - root.metricLabelWidth - root.metricValueWidth
                - 2 * root.metricSpacing)

        Text {
            id: labelText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.metricLabelWidth
            text: label
            font: DTK.fontManager.t7
            // 透明模式分支不接入流光采样（消费端接线规则 5）
            color: root.effectiveTransparent
                ? root.themeTextColor
                : Components.ColorUtils.resolveSiteColor(
                    root.widgetConfig, "dials", "labelTextColor",
                    root.widgetConfig && root.widgetConfig.labelTextColor,
                    "#ffffff", rowCardX + root.metricLabelWidth / 2, root.width)
            opacity: 0.7
            elide: Text.ElideRight
            // 指标名截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
        }

        Text {
            id: valueText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.metricValueWidth
            horizontalAlignment: Text.AlignRight
            text: root.metricText(metricId)
            font: DTK.fontManager.t7
            color: root.effectiveTransparent
                ? root.themeTextColor
                : Components.ColorUtils.resolveSiteColor(
                    root.widgetConfig, "dials", "valueTextColor",
                    root.widgetConfig && root.widgetConfig.valueTextColor,
                    "#ffffff",
                    rowCardX + rowWidth - root.metricValueWidth / 2, root.width)
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
                color: Components.ColorUtils.resolveSiteColor(
                    root.widgetConfig, "dials", "barTrackColor",
                    root.widgetConfig && root.widgetConfig.barTrackColor,
                    "#ffffff", trackCardX + trackWidth / 2, root.width)
                opacity: 0.15
            }

            Rectangle {
                id: barFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width * root.metricUsage(metricId))
                radius: root.barHeight / 2
                // 按进度条自身 x（填充段中心）采样：进度变化时色彩沿轨道横向流动
                color: Components.ColorUtils.resolveSiteColor(
                    root.widgetConfig, "dials", "barColor",
                    root.widgetConfig && root.widgetConfig.barColor, "#4d8cff",
                    trackCardX + Math.max(0, trackWidth * root.metricUsage(metricId)) / 2,
                    root.width)
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
            color: root.titleTextColor
            elide: Text.ElideRight
            // 标题截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
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
            color: root.textColor
            opacity: 0.6
        }
    }
}