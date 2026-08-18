// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "widgets/components" as Components
import "widgets/components/dialslogic.js" as DialsLogic

// 单个小组件实例的配置面板：复用 PanelPopup/PopupHeader，
// 根据 WidgetManager 返回的 settings schema 动态生成控件并即时保存。
PanelPopup {
    id: control

    property string instanceId: ""
    property string widgetId: ""
    property var schema: []
    property var visibleSchema: []
    property var values: ({})
    property var zoneOptions: []
    property var usedZones: []
    property var playerOptions: []
    property string editingColorKey: ""
    property string editingDialKey: ""
    property int editingDialIndex: -1
    property string editingDialField: ""

    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-widget-settings"

    width: 360
    height: 520

    function openFor(instance) {
        control.instanceId = instance
        control.widgetId = Panel.widgetManager.instanceWidgetId(instance)
        control.schema = Panel.widgetManager.widgetSettingsSchema(control.widgetId)
        control.values = Panel.widgetManager.instanceConfig(instance)
        if (control.needsTimezones()) {
            control.zoneOptions = Timezones.zoneOptions()
            control.usedZones = WidgetHost.usedZones(control.instanceId)
        } else {
            control.zoneOptions = []
            control.usedZones = []
        }
        if (control.needsPlayers())
            control.playerOptions = MediaPlayers.players
        else
            control.playerOptions = []
        control.rebuildVisibleSchema()
        control.open()
    }

    function needsTimezones() {
        for (var i = 0; i < control.schema.length; ++i) {
            if (control.schema[i].type === "timezoneList")
                return true
        }
        return false
    }

    function needsPlayers() {
        for (var i = 0; i < control.schema.length; ++i) {
            if (control.schema[i].type === "player")
                return true
        }
        return false
    }

    function rebuildVisibleSchema() {
        var cols = Panel.widgetManager.instanceCols(control.instanceId)
        var result = []
        for (var i = 0; i < control.schema.length; ++i) {
            var item = control.schema[i]
            if (control.widgetId === "systemmonitor" && item.key === "dualColumn"
                && cols < 4) {
                continue
            }
            if (control.widgetId === "player" && item.key === "lockedPlayer"
                && control.values.playerMode !== "locked") {
                continue
            }
            result.push(item)
        }
        control.visibleSchema = result
    }

    function commit(key, value) {
        // 重新赋值整个 values 对象，保证依赖 control.values 的绑定（如
        // timezoneList 的行模型）在保存后重新求值
        var next = {}
        for (var k in control.values)
            next[k] = control.values[k]
        next[key] = value
        control.values = next
        Panel.widgetManager.saveInstanceConfig(control.instanceId, next)
        if (control.widgetId === "player" && key === "playerMode")
            control.rebuildVisibleSchema()
    }

    // 表盘列表编辑：纯计算在 dialslogic.js，这里只做包装与落盘
    function openCustomColor(key, colorText) {
        control.editingColorKey = key
        control.editingDialKey = ""
        colorDialog.openFor(String(colorText))
    }

    function openDialColor(key, index, field, colorText) {
        control.editingColorKey = ""
        control.editingDialKey = key
        control.editingDialIndex = index
        control.editingDialField = field
        colorDialog.openFor(String(colorText))
    }

    function dialList(key) {
        return DialsLogic.dialList(control.values, key)
    }

    function rowOptions(key, index) {
        return DialsLogic.rowOptions(control.usedZones, control.values,
            control.zoneOptions, key, index)
    }

    function zoneIndex(key, index) {
        return DialsLogic.zoneIndex(control.usedZones, control.values,
            control.zoneOptions, key, index)
    }

    function addDial(key) {
        var list = DialsLogic.addDial(control.values, control.usedZones,
            control.zoneOptions, Timezones.systemTimezone, key)
        if (list)
            control.commit(key, list)
    }

    function removeDial(key, index) {
        var list = DialsLogic.removeDial(control.values, key, index)
        if (list)
            control.commit(key, list)
    }

    function setDialZone(key, index, zone) {
        var list = DialsLogic.setDialZone(control.usedZones, control.values,
            key, index, zone)
        if (list)
            control.commit(key, list)
    }

    function dialColorValue(key, index, field) {
        return DialsLogic.dialColorValue(control.values,
            DialsLogic.dialList(control.values, key), index, field)
    }

    function commitDialColor(key, index, field, value) {
        var list = DialsLogic.commitDialColor(control.values, key, index, field, value)
        if (list)
            control.commit(key, list)
    }

    // 自定义颜色取色弹窗（拆分自本面板）：编辑目标由 editing* 状态记录，
    // 确认/取消后清空；commit 与 commitDialColor 走本面板既有路径
    Components.ColorPickerDialog {
        id: colorDialog
        hostPopupWindow: control.popupWindow
        hostHeight: control.height

        onColorCommitted: function(colorText) {
            if (control.editingColorKey.length > 0) {
                control.commit(control.editingColorKey, colorText)
                control.editingColorKey = ""
            } else if (control.editingDialKey.length > 0) {
                control.commitDialColor(control.editingDialKey,
                    control.editingDialIndex, control.editingDialField, colorText)
                control.editingDialKey = ""
                control.editingDialIndex = -1
                control.editingDialField = ""
            }
        }
        onCanceled: {
            control.editingColorKey = ""
            control.editingDialKey = ""
            control.editingDialIndex = -1
            control.editingDialField = ""
        }
    }

    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        Connections {
            target: Panel.widgetManager
            function onInstancesChanged() { control.rebuildVisibleSchema() }
            function onLayoutChanged() { control.rebuildVisibleSchema() }
        }

        Connections {
            target: Timezones
            function onZoneOptionsChanged() {
                if (control.needsTimezones())
                    control.zoneOptions = Timezones.zoneOptions()
            }
        }

        Connections {
            target: MediaPlayers
            function onPlayersChanged() {
                if (control.needsPlayers())
                    control.playerOptions = MediaPlayers.players
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            PopupHeader {
                title: qsTr("Widget settings")
                onCloseRequested: control.close()
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: Panel.widgetManager.displayName(control.widgetId)
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.7
                elide: Text.ElideRight
            }

            Flickable {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                // 底部保留余量：设置项可滚动时最后一行不会紧贴可视区下缘，
                // 避免 DTK Switch 等控件底部因亚像素/DPR 取整被裁掉几行像素。
                contentHeight: settingsColumn.implicitHeight + 16

                // 系统圆角遮罩：滚动内容按弹窗圆角裁剪
                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: settingsScroll.width
                        height: settingsScroll.height
                        radius: DTK.platformTheme.windowRadius
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                ColumnLayout {
                    id: settingsColumn
                    width: parent.width
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        visible: control.visibleSchema.length === 0
                        text: qsTr("This widget has no configurable options")
                        font: DTK.fontManager.t6
                        color: palette.windowText
                        opacity: 0.6
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: control.visibleSchema
                        delegate: Components.SettingsRow {
                            host: control
                        }
                    }
                }
            }
        }
    }
}
