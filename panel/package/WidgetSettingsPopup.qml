// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0

// 单个小组件实例的配置面板：复用 PanelPopup/PopupHeader，
// 根据 WidgetManager 返回的 settings schema 动态生成控件并即时保存。
PanelPopup {
    id: control

    property string instanceId: ""
    property string widgetId: ""
    property var schema: []
    property var values: ({})
    property var zoneOptions: []
    property var usedZones: []
    property string editingColorKey: ""

    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-widget-settings"

    width: 320
    height: 400

    function openFor(instance) {
        control.instanceId = instance
        control.widgetId = Panel.widgetManager.instanceWidgetId(instance)
        control.schema = Panel.widgetManager.widgetSettingsSchema(control.widgetId)
        control.values = Panel.widgetManager.instanceConfig(instance)
        control.zoneOptions = Timezones.zoneOptions()
        control.usedZones = WidgetHost.usedZones(control.instanceId)
        control.open()
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
    }

    function dialList(key) {
        var list = control.values[key]
        return list && list.length !== undefined ? list : []
    }

    // 其它实例已用地区集合（跨实例唯一性）
    function usedZoneSet() {
        var set = {}
        for (var i = 0; i < control.usedZones.length; i++)
            set[control.usedZones[i]] = true
        return set
    }

    // 单行下拉选项：过滤其它实例已用地区，但保留本行当前地区（旧配置可见）
    function rowOptions(key, index) {
        var used = control.usedZoneSet()
        var list = control.dialList(key)
        var dial = index < list.length ? list[index] : null
        var zone = dial && dial.zone ? dial.zone : ""
        var result = []
        for (var i = 0; i < control.zoneOptions.length; i++) {
            var value = control.zoneOptions[i].value
            if (used[value] === undefined || value === zone)
                result.push(control.zoneOptions[i])
        }
        return result
    }

    function zoneIndex(key, index) {
        var options = control.rowOptions(key, index)
        var list = control.dialList(key)
        var dial = index < list.length ? list[index] : null
        var zone = dial && dial.zone ? dial.zone : ""
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === zone)
                return i
        }
        return 0
    }

    function addDial(key) {
        var list = control.dialList(key).slice()
        var used = control.usedZoneSet()
        var defaultZone = Timezones.systemTimezone
        if (defaultZone.length === 0 || used[defaultZone] !== undefined) {
            defaultZone = ""
            for (var i = 0; i < control.zoneOptions.length; i++) {
                if (used[control.zoneOptions[i].value] === undefined) {
                    defaultZone = control.zoneOptions[i].value
                    break
                }
            }
        }
        if (defaultZone.length === 0)
            return

        // 新用户表盘插到补位表盘之前，保证补位表盘始终是尾部可回收的 padding
        var insertAt = list.length
        for (var i = 0; i < list.length; i++) {
            if (list[i].auto === true) {
                insertAt = i
                break
            }
        }
        list.splice(insertAt, 0, { "zone": defaultZone, "auto": false })
        control.commit(key, list)
    }

    function removeDial(key, index) {
        var list = control.dialList(key).slice()
        if (index < 0 || index >= list.length)
            return
        list.splice(index, 1)
        control.commit(key, list)
    }

    function setDialZone(key, index, zone) {
        var list = control.dialList(key).slice()
        if (index < 0 || index >= list.length)
            return
        // 跨实例唯一性：其它实例已用地区不允许改选进来
        if (control.usedZoneSet()[zone] !== undefined)
            return
        // 用户改过的补位表盘视为用户表盘，缩放缩小时不再删除
        list[index] = { "zone": zone, "auto": false }
        control.commit(key, list)
    }

    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            ColorDialog {
                id: customColorDialog
                onAccepted: {
                    if (control.editingColorKey.length > 0) {
                        control.commit(control.editingColorKey,
                            customColorDialog.selectedColor.toString())
                        control.editingColorKey = ""
                    }
                }
            }

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
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight

                ColumnLayout {
                    id: settingsColumn
                    width: parent.width
                    spacing: 12
                    clip: true

                    Text {
                        Layout.fillWidth: true
                        visible: control.schema.length === 0
                        text: qsTr("This widget has no configurable options")
                        font: DTK.fontManager.t6
                        color: palette.windowText
                        opacity: 0.6
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: control.schema
                        delegate: RowLayout {
                            required property var modelData
                            required property int index

                            property string key: modelData.key
                            property string type: modelData.type
                            property var options: modelData.options ? modelData.options : []

                            Layout.fillWidth: true
                            spacing: 8
                            clip: true

                            Text {
                                Layout.preferredWidth: 88
                                visible: type !== "timezoneList"
                                text: modelData.label ? modelData.label : modelData.key
                                font: DTK.fontManager.t6
                                color: palette.windowText
                                elide: Text.ElideRight
                            }

                            Switch {
                                Layout.fillWidth: true
                                visible: type === "boolean"
                                checked: control.values[key] === true
                                onToggled: control.commit(key, checked)
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 120
                                visible: type === "enum"
                                model: options
                                textRole: "label"
                                currentIndex: {
                                    for (var i = 0; i < options.length; i++) {
                                        if (options[i].value === control.values[key])
                                            return i
                                    }
                                    return 0
                                }
                                onActivated: function (i) {
                                    control.commit(key, options[i].value)
                                }
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 120
                                visible: type === "font"
                                editable: false
                                model: Qt.fontFamilies()
                                currentIndex: {
                                    var fonts = Qt.fontFamilies()
                                    var i = fonts.indexOf(control.values[key])
                                    return i >= 0 ? i : 0
                                }
                                onActivated: function (i) {
                                    var fonts = Qt.fontFamilies()
                                    if (i >= 0 && i < fonts.length)
                                        control.commit(key, fonts[i])
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                visible: type === "color"
                                spacing: 6

                                Repeater {
                                    model: options
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index

                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: modelData.value
                                        border.width: control.values[key] === modelData.value ? 2 : 1
                                        border.color: control.values[key] === modelData.value
                                            ? palette.highlight : Qt.rgba(0, 0, 0, 0.25)

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: control.commit(key, modelData.value)
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.25)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        font.pixelSize: 13
                                        color: palette.windowText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton
                                        onClicked: {
                                            control.editingColorKey = key
                                            var current = String(control.values[key] !== undefined
                                                ? control.values[key] : "")
                                            customColorDialog.selectedColor =
                                                current.indexOf("#") === 0 ? current : "#4d8cff"
                                            customColorDialog.open()
                                        }
                                    }
                                }
                            }

                            TextField {
                                Layout.fillWidth: true
                                visible: type === "string" || type === "integer"
                                text: control.values[key] !== undefined && control.values[key] !== null
                                    ? String(control.values[key]) : ""
                                onEditingFinished: {
                                    if (type === "integer") {
                                        var number = parseInt(text, 10)
                                        if (!isNaN(number))
                                            control.commit(key, number)
                                    } else {
                                        control.commit(key, text)
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: type === "timezoneList"
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label ? modelData.label : modelData.key
                                    font: DTK.fontManager.t6
                                    color: palette.windowText
                                }

                                Repeater {
                                    model: control.values[key]
                                    delegate: RowLayout {
                                        required property int index

                                        Layout.fillWidth: true
                                        spacing: 6

                                        ComboBox {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 120
                                            model: control.rowOptions(key, index)
                                            textRole: "label"
                                            currentIndex: control.zoneIndex(key, index)
                                            onActivated: function (i) {
                                                if (i >= 0 && i < control.zoneOptions.length)
                                                    control.setDialZone(key, index,
                                                        control.zoneOptions[i].value)
                                            }
                                        }

                                        Button {
                                            Layout.preferredWidth: 32
                                            text: "✕"
                                            onClicked: control.removeDial(key, index)
                                        }
                                    }
                                }

                                Button {
                                    text: qsTr("Add")
                                    onClicked: control.addDial(key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
