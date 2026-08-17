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

// 自定义颜色取色弹窗（从小组件配置面板拆分）：
// 宿主调用 openFor(colorText) 打开，通过 colorCommitted(colorText) /
// canceled() 信号接收结果；编辑目标（普通配置 key 或表盘字段）与落盘
// 由宿主负责。二级子弹窗以父弹窗为基准：水平在父弹窗左侧，垂直居中。
PanelPopup {
    id: root

    // 父弹窗窗口（transientParent），由宿主注入
    property var hostPopupWindow: null
    // 父弹窗高度（popupY 垂直居中的基准），由宿主注入
    property int hostHeight: 460

    signal colorCommitted(string colorText)
    signal canceled()

    width: 420
    height: 460
    popupWindow: colorDialogWindow
    popupX: -root.width - 8
    popupY: Math.max(0, (root.hostHeight - root.height) / 2)
    windowTitle: "dde-shell/widgettoolbar-widget-color"

    property PanelPopupWindow colorDialogWindow: PanelPopupWindow {
        id: colorDialogWindow
        transientParent: root.hostPopupWindow
    }

    property color parsedColor: "#4d8cff"
    property real hue: 0.0
    property real saturation: 1.0
    property real lightness: 0.5
    property real alpha: 1.0
    readonly property color currentColor: Qt.hsla(hue, saturation, lightness, alpha)

    function openFor(colorText) {
        // 与 ColorUtils 相同的颜色校验规则（避免跨文件 import 依赖）
        var text = String(colorText)
        parsedColor = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(text)
            ? text : "#4d8cff"
        hue = parsedColor.hslHue
        saturation = parsedColor.hslSaturation
        lightness = parsedColor.hslLightness
        alpha = parsedColor.a
        root.open()
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
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        SaturationLightnessPicker {
            id: colorPicker
            objectName: "colorPicker"
            color: root.currentColor
            hue: root.hue

            onColorPicked: function(picked) {
                root.saturation = picked.hslSaturation
                root.lightness = picked.hslLightness
            }

            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        QC.Slider {
            id: hueSlider
            objectName: "hueSlider"
            orientation: Qt.Horizontal
            value: root.hue
            implicitHeight: 20
            onMoved: function() { root.hue = value }

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
            value: root.alpha
            implicitHeight: 20
            onMoved: function() { root.alpha = value }

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
                            color: Qt.rgba(root.currentColor.r,
                                           root.currentColor.g,
                                           root.currentColor.b,
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
            color: root.currentColor
            showAlpha: true

            onColorModified: function(c) {
                root.applyColor(c)
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
                    color: root.currentColor
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
                    root.colorCommitted(root.currentColor.toString())
                    root.close()
                }

                onRejected: {
                    root.canceled()
                    root.close()
                }
            }
        }
    }
}
