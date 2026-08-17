// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0

// 小组件配置面板的单行设置项（schema 驱动的 Repeater 委托，从配置面板拆分）：
// 按 type 分支渲染 boolean/enum/font/player/color/integer/string/timezoneList；
// 所有回写经 host（配置面板）的 commit/openCustomColor/addDial 等函数完成。
RowLayout {
    id: root

    // 宿主注入
    required property var row
    required property var host

    property string key: row.key
    property string type: row.type
    property var options: row.options ? row.options : []

    Layout.fillWidth: true
    spacing: 8

    Text {
        Layout.preferredWidth: 88
        visible: type !== "timezoneList"
        text: row.label ? row.label : row.key
        font: DTK.fontManager.t6
        color: palette.windowText
        elide: Text.ElideRight
    }

    Switch {
        Layout.fillWidth: true
        // DTK Switch 的 indicator 比控件隐式高度高；
        // 再多留 10px 安全高度，覆盖阴影、焦点描边与 DPR 取整。
        Layout.preferredHeight: Math.max(
            implicitHeight,
            (indicator ? indicator.implicitHeight : 0) + 10)
        visible: type === "boolean"
        checked: host.values[key] === true
        onToggled: host.commit(key, checked)
    }

    ComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        visible: type === "enum"
        model: options
        textRole: "label"
        currentIndex: {
            for (var i = 0; i < options.length; i++) {
                if (options[i].value === host.values[key])
                    return i
            }
            return 0
        }
        onActivated: function (i) {
            host.commit(key, options[i].value)
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
            var i = fonts.indexOf(host.values[key])
            return i >= 0 ? i : 0
        }
        onActivated: function (i) {
            var fonts = Qt.fontFamilies()
            if (i >= 0 && i < fonts.length)
                host.commit(key, fonts[i])
        }
    }

    ComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        visible: type === "player"
        enabled: host.playerOptions.length > 0
        model: host.playerOptions
        textRole: "name"
        currentIndex: {
            var current = host.values[key]
            for (var i = 0; i < host.playerOptions.length; i++) {
                if (host.playerOptions[i].service === current)
                    return i
            }
            return 0
        }
        onActivated: function (i) {
            if (i >= 0 && i < host.playerOptions.length)
                host.commit(key, host.playerOptions[i].service)
        }
    }

    Item {
        id: colorSelector
        Layout.fillWidth: true
        Layout.preferredHeight: colorSelector.flowContentHeight
            + 2 * colorSelector.flowPadding
        visible: type === "color"
        clip: true

        readonly property int swatchSize: 24
        readonly property int swatchSpacing: 6
        readonly property int flowPadding: 4
        readonly property int flowRightInset: 24
        readonly property int flowWidth: Math.max(
            swatchSize + swatchSpacing,
            host.width - 2 * 12 - 88 - 8
                - 2 * flowPadding - flowRightInset)
        readonly property int flowColumns: Math.max(1, Math.floor(
            (flowWidth + swatchSpacing)
                / (swatchSize + swatchSpacing)))
        readonly property int flowRows: Math.ceil(
            (options.length + 1) / flowColumns)
        readonly property int flowContentHeight:
            flowRows * swatchSize
                + (flowRows - 1) * swatchSpacing

        property string selectedValue: host.values[key] !== undefined
            ? String(host.values[key]) : ""

        function isKnownOption(value) {
            for (var i = 0; i < options.length; ++i) {
                if (String(options[i].value) === String(value))
                    return true
            }
            return false
        }

        // 定位并动画移动到当前选中项；自定义值没有预设色块时定位到 "+"
        function updateFromValue(value) {
            var known = isKnownOption(String(value))
            var target = null
            for (var i = 0; i < colorFlow.children.length; ++i) {
                var child = colorFlow.children[i]
                if (!child || !child.selectable)
                    continue
                if (known && child.colorValue === String(value)) {
                    target = child
                    break
                }
                if (!known && child.isCustomButton) {
                    target = child
                    break
                }
            }

            if (!target) {
                selectionRing.opacity = 0
                return
            }

            selectionRing.x = colorFlow.x + target.x - 3
            selectionRing.y = colorFlow.y + target.y - 3
            selectionRing.width = target.width + 6
            selectionRing.height = target.height + 6
            selectionRing.opacity = 1
        }

        onSelectedValueChanged: updateFromValue(selectedValue)
        Component.onCompleted: updateFromValue(selectedValue)

        Flow {
            id: colorFlow
            x: colorSelector.flowPadding
            y: colorSelector.flowPadding
            width: colorSelector.flowWidth
            height: colorSelector.flowContentHeight
            spacing: colorSelector.swatchSpacing

            Repeater {
                model: options
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    property bool selectable: true
                    property string colorValue: String(modelData.value)

                    width: 24
                    height: 24
                    radius: 12
                    // 空串色值 = “跟随主题色”（如频谱面板 barColor 缺省），
                    // 色块按当前主题高亮色渲染，避免空色显示为黑块
                    color: String(modelData.value).length > 0
                        ? modelData.value
                        : (DTK.themeType === ApplicationHelper.DarkType
                            ? "#4d8cff" : "#0081ff")
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                    transformOrigin: Item.Center
                    scale: swatchMouse.pressed ? 0.88 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            host.commit(key, modelData.value)
                            colorSelector.updateFromValue(
                                String(modelData.value))
                        }
                    }
                }
            }

            Rectangle {
                id: customColorButton

                property bool selectable: true
                property bool isCustomButton: true
                property string colorValue: ""

                width: 24
                height: 24
                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.25)
                transformOrigin: Item.Center
                scale: customColorMouse.pressed ? 0.88 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 13
                    color: palette.windowText
                }

                MouseArea {
                    id: customColorMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        var current = String(host.values[key] !== undefined
                            ? host.values[key] : "")
                        host.openCustomColor(key, current)
                    }
                }
            }
        }

        Rectangle {
            id: selectionRing
            z: -1
            width: 30
            height: 30
            radius: 15
            color: "transparent"
            border.width: 2
            border.color: palette.highlight
            opacity: 0

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }
        }
    }

    TextField {
        Layout.fillWidth: true
        visible: type === "string" || type === "integer"
        text: host.values[key] !== undefined && host.values[key] !== null
            ? String(host.values[key]) : ""
        onEditingFinished: {
            if (type === "integer") {
                var number = parseInt(text, 10)
                if (!isNaN(number))
                    host.commit(key, number)
            } else {
                host.commit(key, text)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: type === "timezoneList"
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: row.label ? row.label : row.key
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        Repeater {
            // 只有 timezoneList 类型的行才有数组型 dials 配置；
            // 其它行（如 refreshInterval=5000 这类数值）会把
            // 数字误当成 Repeater 的重复次数，瞬间实例化几千个
            // 委托导致 dde-shell GUI 线程卡死。统一走 host.dialList()
            // 保证模型始终是数组或空数组。
            model: host.dialList(key)
            delegate: RowLayout {
                required property int index

                Layout.fillWidth: true
                spacing: 6

                ComboBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    model: host.rowOptions(key, index)
                    textRole: "label"
                    currentIndex: host.zoneIndex(key, index)
                    onActivated: function (i) {
                        var row = host.rowOptions(key, index)
                        if (i >= 0 && i < row.length)
                            host.setDialZone(key, index, row[i].value)
                    }
                }

                Row {
                    Layout.preferredWidth: 4 * 14 + 3 * 4
                    spacing: 4

                    Repeater {
                        model: [
                            { "field": "dialBackground", "hint": "BG" },
                            { "field": "dialColor", "hint": "MK" },
                            { "field": "hourMinuteColor", "hint": "HM" },
                            { "field": "secondColor", "hint": "SS" }
                        ]
                        delegate: Rectangle {
                            required property var modelData

                            width: 14
                            height: 14
                            radius: 7
                            color: host.dialColorValue(key, index, modelData.field)
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.25)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var current = host.dialColorValue(
                                        key, index, modelData.field)
                                    host.openDialColor(key, index,
                                        modelData.field, current)
                                }
                            }
                        }
                    }
                }

                Button {
                    Layout.preferredWidth: 32
                    text: "✕"
                    onClicked: host.removeDial(key, index)
                }
            }
        }

        Button {
            text: qsTr("Add")
            onClicked: host.addDial(key)
        }
    }
}
