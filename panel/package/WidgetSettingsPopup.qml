// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls as QC
import QtQuick.Dialogs.quickimpl
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "widgets/components" as Components

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

    function rebuildVisibleSchema() {
        var cols = Panel.widgetManager.instanceCols(control.instanceId)
        var result = []
        for (var i = 0; i < control.schema.length; ++i) {
            var item = control.schema[i]
            if (control.widgetId === "systemmonitor" && item.key === "dualColumn"
                && cols < 4) {
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
    }

    function openCustomColor(key, colorText, anchorX, anchorY) {
        control.editingColorKey = key
        control.editingDialKey = ""
        customColorDialog.loadColor(String(colorText))
        customColorDialog.open()
    }

    function dialColorValue(key, index, field) {
        var list = control.dialList(key)
        var dial = index < list.length ? list[index] : null
        var value = dial ? dial[field] : undefined
        var fallback = "#ffffff"
        if (field === "dialColor")
            fallback = control.values.dialColor || "#000000"
        else if (field === "hourMinuteColor")
            fallback = control.values.hourMinuteHandColor || "#000000"
        else if (field === "secondColor")
            fallback = control.values.secondHandColor || "#ff4d4f"
        else if (field === "dialBackground")
            fallback = control.values.dialBackgroundColor || "#ffffff"
        return Components.ColorUtils.resolveColor(value, fallback)
    }

    function openDialColor(key, index, field, colorText, anchorX, anchorY) {
        control.editingColorKey = ""
        control.editingDialKey = key
        control.editingDialIndex = index
        control.editingDialField = field
        customColorDialog.loadColor(String(colorText))
        customColorDialog.open()
    }

    function commitDialColor(key, index, field, value) {
        var list = control.dialList(key).slice()
        if (index < 0 || index >= list.length)
            return
        var dial = {}
        for (var k in list[index])
            dial[k] = list[index][k]
        dial[field] = value
        list[index] = dial
        control.commit(key, list)
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

    Item {
        id: customColorDialogHost
        anchors.fill: parent
        z: 1

        property PanelPopupWindow colorDialogWindow: PanelPopupWindow {
            id: customColorDialogWindow
            transientParent: control.popupWindow
        }

        PanelPopup {
            id: customColorDialog

            width: 420
            height: 460
            popupWindow: customColorDialogWindow
            // 二级子弹窗以父弹窗为基准：水平在父弹窗左侧，垂直与父弹窗居中；
            // 不做鼠标位置处理。后续三级子弹窗同样以本弹窗的 popupWindow 为基准。
            popupX: -customColorDialog.width - 8
            popupY: Math.max(0, (control.height - customColorDialog.height) / 2)
            windowTitle: "dde-shell/widgettoolbar-widget-color"

            property color parsedColor: "#4d8cff"
            property real hue: 0.0
            property real saturation: 1.0
            property real lightness: 0.5
            property real alpha: 1.0
            readonly property color currentColor: Qt.hsla(hue, saturation, lightness, alpha)

            function loadColor(colorText) {
                parsedColor = Components.ColorUtils.isValidColor(String(colorText))
                    ? String(colorText) : "#4d8cff"
                hue = parsedColor.hslHue
                saturation = parsedColor.hslSaturation
                lightness = parsedColor.hslLightness
                alpha = parsedColor.a
            }

            function applyColor(c) {
                hue = c.hslHue
                saturation = c.hslSaturation
                lightness = c.hslLightness
                alpha = c.a
            }

            onPopupVisibleChanged: {
                if (popupVisible)
                    focus = true
                else {
                    control.editingColorKey = ""
                    control.editingDialKey = ""
                    control.editingDialIndex = -1
                    control.editingDialField = ""
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                SaturationLightnessPicker {
                    id: colorPicker
                    objectName: "colorPicker"
                    color: customColorDialog.currentColor
                    hue: customColorDialog.hue

                    onColorPicked: function(picked) {
                        customColorDialog.saturation = picked.hslSaturation
                        customColorDialog.lightness = picked.hslLightness
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                QC.Slider {
                    id: hueSlider
                    objectName: "hueSlider"
                    orientation: Qt.Horizontal
                    value: customColorDialog.hue
                    implicitHeight: 20
                    onMoved: function() { customColorDialog.hue = value }

                    handle: PickerHandle {
                        x: hueSlider.leftPadding + (hueSlider.horizontal
                            ? hueSlider.visualPosition * (hueSlider.availableWidth - width)
                            : (hueSlider.availableWidth - width) / 2)
                        y: hueSlider.topPadding + (hueSlider.horizontal
                            ? (hueSlider.availableHeight - height) / 2
                            : hueSlider.visualPosition * (hueSlider.availableHeight - height))
                        picker: hueSlider
                    }

                    background: Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: hueSlider.handle.width / 2
                        anchors.rightMargin: hueSlider.handle.width / 2
                        border.width: 2
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                        radius: 10
                        color: "transparent"

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 10
                            gradient: HueGradient {
                                orientation: Gradient.Horizontal
                            }
                        }
                    }

                    Layout.fillWidth: true
                }

                QC.Slider {
                    id: alphaSlider
                    objectName: "alphaSlider"
                    orientation: Qt.Horizontal
                    value: customColorDialog.alpha
                    implicitHeight: 20
                    onMoved: function() { customColorDialog.alpha = value }

                    handle: PickerHandle {
                        x: alphaSlider.leftPadding + (alphaSlider.horizontal
                            ? alphaSlider.visualPosition * (alphaSlider.availableWidth - width)
                            : (alphaSlider.availableWidth - width) / 2)
                        y: alphaSlider.topPadding + (alphaSlider.horizontal
                            ? (alphaSlider.availableHeight - height) / 2
                            : alphaSlider.visualPosition * (alphaSlider.availableHeight - height))
                        picker: alphaSlider
                    }

                    background: Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: alphaSlider.handle.width / 2
                        anchors.rightMargin: alphaSlider.handle.width / 2
                        border.width: 2
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                        radius: 10
                        color: "transparent"

                        Image {
                            anchors.fill: alphaSliderGradient
                            source: "qrc:/qt-project.org/imports/QtQuick/Dialogs/quickimpl/images/checkers.png"
                            fillMode: Image.Tile
                        }

                        Rectangle {
                            id: alphaSliderGradient
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 10
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.rgba(customColorDialog.currentColor.r,
                                                   customColorDialog.currentColor.g,
                                                   customColorDialog.currentColor.b,
                                                   1)
                                }
                            }
                        }
                    }

                    Layout.fillWidth: true
                }

                ColorInputs {
                    id: inputs
                    objectName: "colorInputs"
                    color: customColorDialog.currentColor
                    showAlpha: true

                    onColorModified: function(c) {
                        customColorDialog.applyColor(c)
                    }

                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        id: colorPreview
                        implicitWidth: 32
                        implicitHeight: 32
                        border.width: 2
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                        color: "transparent"

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            source: "qrc:/qt-project.org/imports/QtQuick/Dialogs/quickimpl/images/checkers.png"
                            fillMode: Image.Tile
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            color: customColorDialog.currentColor
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    QC.DialogButtonBox {
                        id: buttonBox
                        standardButtons: QC.DialogButtonBox.Ok
                            | QC.DialogButtonBox.Cancel
                        spacing: 12

                        onAccepted: {
                            var colorText = customColorDialog.currentColor.toString()
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
                            customColorDialog.close()
                        }

                        onRejected: {
                            control.editingColorKey = ""
                            control.editingDialKey = ""
                            control.editingDialIndex = -1
                            control.editingDialField = ""
                            customColorDialog.close()
                        }
                    }
                }
            }
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
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                // 底部保留余量：设置项可滚动时最后一行不会紧贴可视区下缘，
                // 避免 DTK Switch 等控件底部因亚像素/DPR 取整被裁掉几行像素。
                contentHeight: settingsColumn.implicitHeight + 12
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
                        delegate: RowLayout {
                            required property var modelData
                            required property int index

                            property string key: modelData.key
                            property string type: modelData.type
                            property var options: modelData.options ? modelData.options : []

                            Layout.fillWidth: true
                            spacing: 8

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
                                // DTK Switch 的 indicator 比控件隐式高度高；
                                // 再多留 6px 安全高度，覆盖阴影、焦点描边与 DPR 取整。
                                Layout.preferredHeight: Math.max(
                                    implicitHeight,
                                    (indicator ? indicator.implicitHeight : 0) + 6)
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
                                    control.width - 2 * 12 - 88 - 8
                                        - 2 * flowPadding - flowRightInset)
                                readonly property int flowColumns: Math.max(1, Math.floor(
                                    (flowWidth + swatchSpacing)
                                        / (swatchSize + swatchSpacing)))
                                readonly property int flowRows: Math.ceil(
                                    (options.length + 1) / flowColumns)
                                readonly property int flowContentHeight:
                                    flowRows * swatchSize
                                        + (flowRows - 1) * swatchSpacing

                                property string selectedValue: control.values[key] !== undefined
                                    ? String(control.values[key]) : ""

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
                                            color: modelData.value
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
                                                    control.commit(key, modelData.value)
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
                                                var current = String(control.values[key] !== undefined
                                                    ? control.values[key] : "")
                                                var anchor = customColorButton.mapToItem(
                                                    customColorDialog.parent,
                                                    customColorButton.width / 2,
                                                    customColorButton.height)
                                                control.openCustomColor(key, current,
                                                    anchor.x, anchor.y)
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
                                    // 只有 timezoneList 类型的行才有数组型 dials 配置；
                                    // 其它行（如 refreshInterval=5000 这类数值）会把
                                    // 数字误当成 Repeater 的重复次数，瞬间实例化几千个
                                    // 委托导致 dde-shell GUI 线程卡死。统一走 dialList()
                                    // 保证模型始终是数组或空数组。
                                    model: control.dialList(key)
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
                                                var row = control.rowOptions(key, index)
                                                if (i >= 0 && i < row.length)
                                                    control.setDialZone(key, index, row[i].value)
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
                                                    color: control.dialColorValue(
                                                        key, index, modelData.field)
                                                    border.width: 1
                                                    border.color: Qt.rgba(0, 0, 0, 0.25)

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onClicked: {
                                                            var current = control.dialColorValue(
                                                                key, index, modelData.field)
                                                            var anchor = parent.mapToItem(
                                                                customColorDialog.parent,
                                                                parent.width / 2,
                                                                parent.height)
                                                            control.openDialColor(key, index,
                                                                modelData.field, current,
                                                                anchor.x, anchor.y)
                                                        }
                                                    }
                                                }
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
