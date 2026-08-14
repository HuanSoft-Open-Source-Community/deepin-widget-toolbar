// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import "../components" as Components

// 内置示例小组件：世界时间。
// 数字模式显示城市列表；指针模式按宿主格数排布表盘，
// 表盘不足时从末位 UTC 偏移 +1 小时生成，越过 +14 回绕到 -12，
// 并始终去重。
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
    property bool analogMode: widgetConfig && widgetConfig.clockMode === "analog"
    property bool showLabels: widgetConfig && widgetConfig.showLabels !== undefined
        ? widgetConfig.showLabels : true
    property bool highlightLocal: widgetConfig && widgetConfig.highlightLocal !== undefined
        ? widgetConfig.highlightLocal : true
    property int customOffset: widgetConfig && widgetConfig.customOffset !== undefined
        && widgetConfig.customOffset !== null ? Number(widgetConfig.customOffset) : -99
    property int hostCols: 4
    property int hostRows: 2
    property int dialCount: Math.max(1, hostCols * hostRows)
    property real localOffset: {
        var now = new Date()
        return -now.getTimezoneOffset() / 60
    }

    property var baseCities: [
        { "name": qsTr("Beijing"), "offset": 8 },
        { "name": qsTr("Tokyo"), "offset": 9 },
        { "name": qsTr("London"), "offset": 0 },
        { "name": qsTr("New York"), "offset": -5 }
    ]
    property var times: []
    property var visibleCities: []
    property var timezoneSequence: []
    property int layoutSpacing: 6
    property int rowHeight: Math.max(18,
        Math.floor((content.height - 28 - layoutSpacing * (visibleCities.length + 1))
            / visibleCities.length))
    property int titlePixelSize: Math.max(11, Math.min(20, Math.round(content.width * 0.04)))
    property int cityPixelSize: Math.max(8, Math.min(18, Math.round(rowHeight * 0.42)))

    function offsetLabel(offset) {
        if (offset >= 0)
            return qsTr("UTC+") + offset
        return qsTr("UTC") + offset
    }

    function isCustomOffset(offset) {
        return offset !== -99 && offset >= -12 && offset <= 14
    }

    function cityTime(offset) {
        var now = new Date()
        var utcMs = now.getTime() + now.getTimezoneOffset() * 60000
        return new Date(utcMs + offset * 3600000)
    }

    function updateTimes() {
        var list = []
        for (var i = 0; i < root.visibleCities.length; i++)
            list.push(Qt.formatTime(root.cityTime(root.visibleCities[i].offset), "HH:mm"))
        root.times = list
    }

    function rebuildCities() {
        var list = root.baseCities.slice()
        if (root.isCustomOffset(root.customOffset)) {
            var exists = false
            for (var i = 0; i < list.length; i++) {
                if (list[i].offset === root.customOffset) {
                    exists = true
                    break
                }
            }
            if (!exists)
                list.push({ "name": root.offsetLabel(root.customOffset), "offset": root.customOffset })
        }
        root.visibleCities = list
    }

    function rebuildSequence() {
        var used = {}
        var list = []

        function add(offset, name) {
            if (used[offset] !== undefined)
                return
            used[offset] = true
            list.push({ "offset": offset, "name": name })
        }

        for (var i = 0; i < root.baseCities.length; i++)
            add(root.baseCities[i].offset, root.baseCities[i].name)
        if (root.isCustomOffset(root.customOffset))
            add(root.customOffset, root.offsetLabel(root.customOffset))

        while (list.length > root.dialCount)
            list.pop()

        var cursor = list.length > 0 ? list[list.length - 1].offset : 0
        var guard = 0
        while (list.length < root.dialCount && guard < 200) {
            guard++
            cursor = cursor >= 14 ? -12 : cursor + 1
            if (used[cursor] === undefined)
                add(cursor, root.offsetLabel(cursor))
        }
        root.timezoneSequence = list
    }

    onCustomOffsetChanged: {
        root.rebuildCities()
        root.rebuildSequence()
        root.updateTimes()
    }
    onDialCountChanged: root.rebuildSequence()
    onWidgetConfigChanged: {
        root.rebuildCities()
        root.rebuildSequence()
        root.updateTimes()
    }
    Component.onCompleted: {
        root.rebuildCities()
        root.rebuildSequence()
        root.updateTimes()
    }

    Column {
        id: content
        visible: !root.analogMode
        anchors.fill: parent
        spacing: root.layoutSpacing

        Text {
            text: qsTr("World Time")
            font.pixelSize: root.titlePixelSize
            color: palette.windowText
        }

        Repeater {
            model: root.visibleCities
            delegate: Item {
                width: content.width
                height: root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    visible: root.highlightLocal
                        && Math.abs(modelData.offset - root.localOffset) < 0.001
                    color: palette.highlight
                    opacity: 0.16
                }

                Text {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: content.width / 2 - 4
                    text: modelData.name
                    font.pixelSize: root.cityPixelSize
                    color: palette.windowText
                    opacity: 0.8
                    elide: Text.ElideRight
                }

                Text {
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: content.width / 2 - 4
                    horizontalAlignment: Text.AlignRight
                    text: index < root.times.length ? root.times[index] : "--:--"
                    font.pixelSize: root.cityPixelSize
                    color: palette.windowText
                }
            }
        }
    }

    Grid {
        id: analogGrid
        visible: root.analogMode
        anchors.fill: parent
        columns: root.hostCols
        rows: root.hostRows
        spacing: 2

        Repeater {
            model: root.timezoneSequence
            delegate: Item {
                required property var modelData

                width: Math.max(1,
                    (analogGrid.width - (root.hostCols - 1) * analogGrid.spacing) / root.hostCols)
                height: Math.max(1,
                    (analogGrid.height - (root.hostRows - 1) * analogGrid.spacing) / root.hostRows)

                Components.AnalogClock {
                    anchors.fill: parent
                    utcOffset: modelData.offset
                    label: modelData.name
                    showLabels: root.showLabels
                    highlighted: root.highlightLocal
                        && Math.abs(modelData.offset - root.localOffset) < 0.001
                    accentColor: palette.highlight
                }
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.analogMode
        triggeredOnStart: true
        onTriggered: root.updateTimes()
    }
}
