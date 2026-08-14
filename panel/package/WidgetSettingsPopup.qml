// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// 单个小组件实例的配置面板：复用 PanelPopup/PopupHeader，
// 根据 WidgetManager 返回的 settings schema 动态生成控件并即时保存。
PanelPopup {
    id: control

    property string instanceId: ""
    property string widgetId: ""
    property var schema: []
    property var values: ({})
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
        control.open()
    }

    function commit(key, value) {
        control.values[key] = value
        Panel.widgetManager.saveInstanceConfig(control.instanceId, control.values)
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
                        }
                    }
                }
            }
        }
    }
}
