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
    // 同级三级面板（应用选择）避让：对方正打开时向左让出宽度，避免叠窗
    property real avoidOffsetX: 0
    // 整卡唯一互斥授权（宿主注入）：本部位是否被允许进入流光。整卡已有
    // 其它部位占用流光时本部位不响应（不进流光预览，OK 只提交纯色）
    property bool flowGranted: true

    signal colorCommitted(string colorText)
    signal canceled()

    width: 420
    height: 460
    popupWindow: colorDialogWindow
    popupX: -root.width - 8 - root.avoidOffsetX
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

    // ── 选色卡彩蛋：Konami 连招命中后进入「流光预览」态 ──────────────────
    // 预览只影响弹窗内的显示，不写配置；点 OK 才把 @flow: 值交给宿主。
    property bool flowMode: false
    property string flowBaseColor: "#4d8cff"   // 流光内嵌原色（纯色字符串）
    property int comboIndex: 0
    readonly property var comboSequence: ["Up", "Up", "Down", "Down",
                                          "Left", "Right", "Left", "Right", "B", "A"]
    // 只有真正的文本编辑控件持有焦点时才让出连招键。
    // 不能用 typeof item.text === "string"：Button 也有 text，
    // 点过 OK/Cancel 后焦点停在按钮上会让连招被永久禁用。
    readonly property bool textEditing: {
        var item = root.colorDialogWindow.activeFocusItem
        return !!item && (item instanceof TextInput || item instanceof TextEdit)
    }

    function openFor(colorText, granted) {
        // 与 ColorUtils 相同的颜色校验规则（避免跨文件 import 依赖）；
        // 流光值先剥掉前缀，弹窗内始终以纯色作为编辑基准
        var text = String(colorText)
        var prefixed = text.indexOf("@flow:") === 0
        var inner = prefixed ? text.slice(6) : text
        var innerValid = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(inner)
        var g = granted === undefined ? true : !!granted
        root.flowGranted = g
        // 内嵌色非法、或本部位未被授权（整卡已被其它部位占用流光）时
        // 按纯色值处理，不进入流光预览
        var flow = prefixed && innerValid && g
        if (!innerValid)
            inner = "#4d8cff"
        parsedColor = inner
        hue = parsedColor.hslHue
        saturation = parsedColor.hslSaturation
        lightness = parsedColor.hslLightness
        alpha = parsedColor.a
        flowBaseColor = inner
        resetCombo()
        flowMode = flow
        root.open()
    }

    function applyColor(c) {
        hue = c.hslHue
        saturation = c.hslSaturation
        lightness = c.hslLightness
        alpha = c.a
    }

    function resetCombo() {
        root.comboIndex = 0
        comboTimeout.stop()
    }

    // 命中/再次命中连招：在「流光预览」与「原色」之间切换。
    // 整卡唯一互斥：本部位未被授权（已被其它部位占用流光）时不响应，
    // 保持原色，避免用户为空位白费功夫（开关不生效即不进预览）
    function toggleFlow() {
        if (!root.flowGranted)
            return
        if (root.flowMode) {
            root.flowMode = false
            root.parsedColor = root.flowBaseColor   // property color 接收字符串自动转换
            root.applyColor(root.parsedColor)
        } else {
            root.flowBaseColor = root.currentColor.toString()
            root.flowMode = true
        }
    }

    function handleComboKey(key) {
        if (!root.popupVisible || root.textEditing)
            return
        if (key === root.comboSequence[root.comboIndex]) {
            // 3 秒窗口从首键开始计时，不在每次按键时续期
            if (root.comboIndex === 0)
                comboTimeout.restart()
            root.comboIndex += 1
            if (root.comboIndex >= root.comboSequence.length) {
                root.resetCombo()
                root.toggleFlow()
            }
        } else {
            root.resetCombo()
        }
    }

    onPopupVisibleChanged: {
        if (root.popupVisible) {
            // focus = true 在已为 true 时不产生焦点转移；先把上次会话
            // 遗留在按钮 / 输入框上的 activeFocusItem 清掉，再强制落回弹窗
            var prev = root.colorDialogWindow.activeFocusItem
            if (prev && prev !== root)
                prev.focus = false
            root.forceActiveFocus()
        } else {
            root.resetCombo()
            root.flowMode = false
        }
    }

    // 只在状态真变化时增减共享时钟引用，避免计数泄漏
    onFlowModeChanged: {
        if (root.flowMode)
            ColorUtils.acquireFlow()
        else
            ColorUtils.releaseFlow()
    }
    // 弹窗对象被销毁时若仍处于流光态，补一次归还，避免引用计数悬挂
    Component.onDestruction: if (root.flowMode) ColorUtils.releaseFlow()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // 取色区（色板 + 两条滑杆 + 色值输入）整体包一层：
        // 流光遮罩要覆盖这一整块，但不能压住下方按钮行
        Item {
            id: pickerArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                SaturationLightnessPicker {
                    id: colorPicker
                    objectName: "colorPicker"
                    color: root.currentColor
                    hue: root.hue
                    enabled: !root.flowMode
                    opacity: root.flowMode ? 0.4 : 1.0

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
                    enabled: !root.flowMode
                    opacity: root.flowMode ? 0.4 : 1.0
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
                        border.color: ColorUtils.hairline
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
                    enabled: !root.flowMode
                    opacity: root.flowMode ? 0.4 : 1.0
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
                        border.color: ColorUtils.hairline
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
                    enabled: !root.flowMode
                    opacity: root.flowMode ? 0.4 : 1.0

                    onColorModified: function(c) {
                        root.applyColor(c)
                    }

                    Layout.fillWidth: true
                }
            }

            // 流光预览遮罩：7 个色相沿色环均匀铺开的横向渐变，颜色随共享相位
            // 跑马；不参与布局占位，纯覆盖在取色区之上（按钮行不在其内）
            Rectangle {
                id: flowOverlay
                z: 1
                anchors.fill: parent
                visible: root.flowMode
                opacity: 0.75
                radius: 8
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 0 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 1 / 6
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 1 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 2 / 6
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 2 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 3 / 6
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 3 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 4 / 6
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 4 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 5 / 6
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 5 * 0.08, ColorUtils.dark)
                    }
                    GradientStop {
                        position: 1
                        color: ColorUtils.flowColorAt(root.flowBaseColor, ColorUtils.flowPhase, 6 * 0.08, ColorUtils.dark)
                    }
                }
            }

            // 连招键挂在本 Item 之下：PanelPopup 的默认属性是 popup.children
            //（只收可视 Item），Timer/Shortcut 写在根下会被拒绝。
            // 序列未开始时只拦截 Up，避免吞掉滑杆/输入框的正常按键；
            // 序列进行中才拦截其余键，用于「按错即重置」
            Shortcut {
                sequence: "Up"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing
                onActivated: root.handleComboKey("Up")
            }

            Shortcut {
                sequence: "Down"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing && root.comboIndex > 0
                onActivated: root.handleComboKey("Down")
            }

            Shortcut {
                sequence: "Left"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing && root.comboIndex > 0
                onActivated: root.handleComboKey("Left")
            }

            Shortcut {
                sequence: "Right"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing && root.comboIndex > 0
                onActivated: root.handleComboKey("Right")
            }

            Shortcut {
                sequence: "B"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing && root.comboIndex > 0
                onActivated: root.handleComboKey("B")
            }

            Shortcut {
                sequence: "A"
                autoRepeat: false
                enabled: root.popupVisible && !root.textEditing && root.comboIndex > 0
                onActivated: root.handleComboKey("A")
            }

            Timer {
                id: comboTimeout
                interval: 3000
                repeat: false
                onTriggered: root.resetCombo()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                id: colorPreview
                implicitWidth: 32
                implicitHeight: 32
                border.width: 2
                border.color: ColorUtils.hairline
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
                    // 流光预览时预览块跟着跑马，退出后回到原色绑定
                    color: root.flowMode
                        ? ColorUtils.resolveColor("@flow:" + root.flowBaseColor, "#4d8cff", 0)
                        : root.currentColor
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // 自定义按钮：Qt 标准按钮文案依赖 qt_ 翻译包，本环境不保证加载，
            // 改走本插件 ts（qsTr），保证三级面板按钮随语言翻译
            Button {
                text: qsTr("Cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                text: qsTr("OK")
                onClicked: {
                    // 只有确认才把流光值（@flow: 前缀）写回配置
                    root.colorCommitted(root.flowMode
                        ? ColorUtils.flowValue(root.flowBaseColor)
                        : root.currentColor.toString())
                    root.close()
                }
            }
        }
    }
}
