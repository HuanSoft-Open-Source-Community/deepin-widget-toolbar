// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components
import "dialslogic.js" as DialsLogic

// 内置小组件：世界时间（逐表盘自定义）。
// 每块表盘由控制中心时区下拉定义：地区名与 UTC 偏移都由所选时区决定，
// 无需维护偏移文本框。表盘列表按实例持久化（widgetConfig.dials，
// 元素为 {zone, auto}），数字模式显示全部表盘，指针模式显示前
// hostCols*hostRows 个表盘，表盘可少于格子数并留空。
// 新实例缺省为指针模式并预置四块表盘（默认 2×2 恰好放满）：当前时区一块，
// 其余三块取旧版四城市（北京/东京/伦敦/纽约）中不与当前时区重复的前三个。
// 预置仅在实例尚无任何已保存配置（config 文件不存在）时生成并持久化；
// 用户在设置中清空表盘后不再自动补回。
// 只有“调整小组件尺寸”事件会在指针模式下补满格子：缩小先删尾部补位表盘
// （auto=true），用户表盘保留；放大从末位偏移 +1 小时、越过 +14 回绕到 -12、
// 按偏移去重，取该偏移下 GetZoneList 顺序的第一个时区生成补位表盘（auto=true）；
// 无对应时区的偏移跳过。手动增删、切换数字模式、首次加载都不补位。
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    instanceId: ""
    property bool analogMode: widgetConfig && widgetConfig.clockMode === "analog"
    property bool preloadTime: widgetConfig && widgetConfig.preloadTime !== undefined
        ? widgetConfig.preloadTime : true
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#000000")
    textColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.textColor, "#ffffff")
    property color dialBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.dialBackgroundColor, "#ffffff")
    property color dialColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.dialColor, "#000000")
    property color hourMinuteHandColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.hourMinuteHandColor, "#000000")
    property color secondHandColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.secondHandColor, "#ff4d4f")
    highlightColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.highlightColor, "#4d8cff")
    property bool panelVisible: Panel.visible
    property bool showLabels: widgetConfig && widgetConfig.showLabels !== undefined
        ? widgetConfig.showLabels : true
    // 缺省不高亮本机时区（可在设置中开启）
    property bool highlightLocal: widgetConfig && widgetConfig.highlightLocal !== undefined
        ? widgetConfig.highlightLocal : false
    hostCols: 4
    hostRows: 2
    property int dialCount: Math.max(1, hostCols * hostRows)
    property real localOffset: {
        var now = new Date()
        return -now.getTimezoneOffset() / 60
    }

    // 持久化表盘（{zone, auto}）与渲染信息（{zone, name, offset}）
    property var dials: []
    property var zoneInfos: []
    property var times: []
    property int lastSlotCount: -1
    property bool resizePending: false

    // 旧版固定四城市（北京/东京/伦敦/纽约）对应的控制中心时区 id，
    // 新实例缺省四表盘中“老四样之三”的来源
    property var legacyFourZones: [
        "Asia/Shanghai",
        "Asia/Tokyo",
        "Europe/London",
        "America/New_York"
    ]
    // 本实例缺省表盘已预置（或确认无需预置），避免反复补回
    property bool defaultDialsSeeded: false

    property int layoutSpacing: 6
    property int rowHeight: Math.max(18,
        Math.floor((content.height - 28 - layoutSpacing * (zoneInfos.length + 1))
            / Math.max(1, zoneInfos.length)))
    property int titlePixelSize: Math.max(11, Math.min(20, Math.round(content.width * 0.04)))
    property int cityPixelSize: Math.max(8, Math.min(18, Math.round(rowHeight * 0.42)))

    function nowMs() {
        return root.preloadTime ? ClockTime.epochMs : Date.now()
    }

    function cityTime(offset) {
        var ms = root.nowMs()
        var local = new Date(ms)
        var utcMs = ms + local.getTimezoneOffset() * 60000
        return new Date(utcMs + offset * 3600000)
    }

    function zoneName(zoneId) {
        var name = Timezones.displayName(zoneId)
        if (name.length === 0) {
            var parts = zoneId.split("/")
            name = (parts.length > 0 ? parts[parts.length - 1] : zoneId).replace(/_/g, " ")
        }
        return name
    }

    function zoneOffset(zoneId) {
        return Timezones.offsetSeconds(zoneId) / 3600
    }

    // 表盘列表纯计算（缺省预置/补位/收缩）在 dialslogic.js
    function defaultDialList() {
        return DialsLogic.defaultDialList(Timezones.systemTimezone,
            Timezones.userTimezones, root.legacyFourZones)
    }

    // 实例配置文件路径；dataDir/instanceId 由宿主注入，就绪前返回空
    function configFilePath() {
        if (root.instanceId.length === 0 || root.dataDir.length === 0)
            return ""
        return root.dataDir + "/" + root.instanceId + ".config.json"
    }

    // 新实例缺省预置四表盘并持久化；已有任何已保存配置（含用户清空）则不再补。
    // 时区代理未就绪（systemTimezone 为空）时留待 systemTimezoneChanged 重试。
    function seedDefaultDials() {
        if (root.defaultDialsSeeded)
            return
        var path = root.configFilePath()
        if (path.length === 0)
            return
        if (FileIO.exists(path)) {
            root.defaultDialsSeeded = true
            return
        }
        if (Timezones.systemTimezone.length === 0
            && Timezones.userTimezones.length === 0)
            return
        var list = root.defaultDialList()
        if (list.length === 0)
            return
        if (WidgetHost.saveConfig(root.instanceId, { "dials": list })) {
            root.defaultDialsSeeded = true
            // 保存成功后先本地生效，避免宿主回写前的空窗期显示“暂无表盘”
            root.applyDials(list)
        }
    }

    function updateTimes() {
        var list = []
        for (var i = 0; i < root.zoneInfos.length; i++)
            list.push(Qt.formatTime(root.cityTime(root.zoneInfos[i].offset), "HH:mm"))
        root.times = list
    }

    function applyDials(list) {
        root.dials = list

        var infos = []
        for (var j = 0; j < list.length; j++) {
            infos.push({
                "zone": list[j].zone,
                "name": root.zoneName(list[j].zone),
                "offset": root.zoneOffset(list[j].zone),
                "dialBackground": Components.ColorUtils.resolveColor(
                    list[j].dialBackground, root.dialBackgroundColor),
                "dialColor": Components.ColorUtils.resolveColor(
                    list[j].dialColor, root.dialColor),
                "hourMinuteColor": Components.ColorUtils.resolveColor(
                    list[j].hourMinuteColor, root.hourMinuteHandColor),
                "secondColor": Components.ColorUtils.resolveColor(
                    list[j].secondColor, root.secondHandColor)
            })
        }
        root.zoneInfos = infos
        root.updateTimes()
    }

    function rebuildDials() {
        var source = root.widgetConfig && root.widgetConfig.dials
        var list = []
        if (source && source.length !== undefined) {
            for (var i = 0; i < source.length; i++) {
                var item = source[i]
                if (item && typeof item.zone === "string" && item.zone.length > 0) {
                    list.push({
                        "zone": item.zone,
                        "auto": item.auto === true,
                        "dialBackground": item.dialBackground,
                        "dialColor": item.dialColor,
                        "hourMinuteColor": item.hourMinuteColor,
                        "secondColor": item.secondColor
                    })
                }
            }
        }
        // 尚无任何表盘时尝试预置缺省四表盘（首次加载的兜底入口；
        // 时区/注入未就绪时由下方信号处理重试）
        if (list.length === 0)
            root.seedDefaultDials()
        root.applyDials(list)
    }

    function fillDials(target) {
        return DialsLogic.fillDials(root.dials, target, {
            "zoneOffset": function (zoneId) { return root.zoneOffset(zoneId) },
            "firstZoneForOffset": function (offsetHours, excludeZones) {
                return Timezones.firstZoneForOffset(offsetHours, excludeZones)
            },
            "otherUsedZones": root.instanceId.length > 0
                ? WidgetHost.usedZones(root.instanceId) : []
        })
    }

    function shrinkDials() {
        return DialsLogic.shrinkDials(root.dials, root.hostCols * root.hostRows)
    }

    function persistDials(list) {
        if (root.instanceId.length === 0)
            return
        // 保存成功后先本地生效，避免宿主回写前的连续快速缩放使用旧列表
        if (WidgetHost.saveConfig(root.instanceId, { "dials": list }))
            root.applyDials(list)
    }

    function handleResize() {
        var slots = root.hostCols * root.hostRows
        if (root.lastSlotCount >= 0 && slots !== root.lastSlotCount && root.analogMode) {
            if (slots > root.dials.length) {
                var grown = root.fillDials(slots)
                if (grown.length !== root.dials.length)
                    root.persistDials(grown)
            } else if (slots < root.dials.length) {
                var shrunk = root.shrinkDials()
                if (shrunk.length !== root.dials.length)
                    root.persistDials(shrunk)
            }
        }
        root.lastSlotCount = slots
    }

    function scheduleResize() {
        if (root.resizePending)
            return
        root.resizePending = true
        resizeTimer.restart()
    }

    onHostColsChanged: root.scheduleResize()
    onHostRowsChanged: root.scheduleResize()
    onWidgetConfigChanged: root.rebuildDials()
    onPreloadTimeChanged: if (!root.analogMode) root.updateTimes()
    onVisibleChanged: if (visible && !root.analogMode) root.updateTimes()
    onPanelVisibleChanged: if (panelVisible && !root.analogMode) root.updateTimes()
    // 注入/时区代理就绪后重试缺省表盘预置
    onInstanceIdChanged: root.seedDefaultDials()
    onDataDirChanged: root.seedDefaultDials()
    Component.onCompleted: {
        root.rebuildDials()
        // 宿主对 hostCols/hostRows 的首次注入可能晚于 onCompleted，
        // 延迟一拍再记录基准尺寸，避免把首次注入误判为“缩放”
        Qt.callLater(function () {
            root.lastSlotCount = root.hostCols * root.hostRows
        })
    }

    Timer {
        id: resizeTimer
        interval: 0
        repeat: false
        onTriggered: {
            root.resizePending = false
            root.handleResize()
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 24
        visible: root.zoneInfos.length === 0
        text: qsTr("No dials yet. Add timezones in widget settings.")
        font: DTK.fontManager.t5
        color: root.effectiveTransparent ? root.themeTextColor : palette.windowText
        opacity: 0.6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    // 数字模式列表视图（拆分至 DigitalList.qml）
    DigitalList {
        id: content
        visible: !root.analogMode
        zoneInfos: root.zoneInfos
        times: root.times
        layoutSpacing: root.layoutSpacing
        rowHeight: root.rowHeight
        titlePixelSize: root.titlePixelSize
        cityPixelSize: root.cityPixelSize
        highlightLocal: root.highlightLocal
        localOffset: root.localOffset
        textColor: root.textColor
        effectiveTransparent: root.effectiveTransparent
        themeTextColor: root.themeTextColor
    }

    // 指针模式表盘网格视图（拆分至 DialGrid.qml）
    DialGrid {
        id: analogGrid
        visible: root.analogMode
        zoneInfos: root.zoneInfos
        hostCols: root.hostCols
        hostRows: root.hostRows
        showLabels: root.showLabels
        highlightLocal: root.highlightLocal
        localOffset: root.localOffset
        highlightColor: root.highlightColor
        textColor: root.textColor
        effectiveTransparent: root.effectiveTransparent
        themeTextColor: root.themeTextColor
        preloadTime: root.preloadTime
        active: root.panelVisible
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.analogMode && !root.preloadTime && root.panelVisible && root.visible
        onTriggered: root.updateTimes()
    }

    Connections {
        target: ClockTime
        enabled: root.preloadTime && root.panelVisible && root.visible
        function onEpochMsChanged() {
            if (!root.analogMode)
                root.updateTimes()
        }
    }

    // 时区代理异步就绪后重试缺省表盘预置
    Connections {
        target: Timezones
        function onSystemTimezoneChanged() {
            root.seedDefaultDials()
        }
    }

    // DST 切换会改变表盘当前偏移，每小时重算渲染信息
    Timer {
        interval: 3600000
        repeat: true
        running: true
        onTriggered: root.rebuildDials()
    }
}
