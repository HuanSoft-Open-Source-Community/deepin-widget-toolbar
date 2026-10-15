// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.dtk.style 1.0 as DStyle
import org.deepin.ds 1.0
import "widgets/components" as Components

// 添加小组件弹出面板：
//  - 基于 PanelPopup（DPanel 辅助窗口）：无 Qt 窗口标题、失焦自动关闭、跟随主窗口定位
//  - 与侧栏一致的透明毛玻璃风格（PopupWindow 自带 StyledBehindWindowBlur + 系统圆角）
//  - 右上角圆形叉号关闭
//  - 内置小组件可添加；已添加实例可移除；第三方小组件可卸载（内置不可卸载）
PanelPopup {
    id: control

    // 弹在侧栏面板左侧；popupY 默认 0（顶部对齐），打开前宿主按触发位置
    // 重定位（main.qml positionPopup），弹窗垂直趋向鼠标指针所在高度
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-add"

    width: 320
    height: 520

    // 已添加实例列表（随 WidgetManager 信号刷新）
    property var instanceIds: Panel.widgetManager ? Panel.widgetManager.instanceIds() : []
    // 安装/卸载操作结果提示（临时显示）
    property string statusText: ""
    property bool statusError: false
    // 网络协议弹窗记录的待添加组件：同意后立即添加；不同意/Esc/关闭则清空不添加
    property string pendingNetworkWidgetId: ""
    function showStatus(text, isError) {
        control.statusText = text
        control.statusError = isError
        statusTimer.restart()
    }

    // 右上角圆形叉号关闭按钮
    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        // 非可视辅助对象必须放在内容卡片内部：
        // PanelPopup 的 default property 只接受可视 Item，直接挂根下会报
        // "Cannot assign object to list property popupContent"
        Timer {
            id: statusTimer
            interval: 3000
            repeat: false
            onTriggered: control.statusText = ""
        }
        Connections {
            target: Panel.widgetManager
            function onInstancesChanged() {
                instanceIds = Panel.widgetManager.instanceIds()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ===== 标题栏：标题 + 圆形叉号 =====
            PopupHeader {
                title: qsTr("Add widgets")
                onCloseRequested: control.close()
            }

            // ===== 分区：可用小组件（内置 + 已安装第三方，可添加） =====
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: qsTr("Available widgets")
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.7
            }

            ListView {
                id: builtinList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 200
                clip: true
                spacing: 4
                model: Panel.widgetListModel

                // 系统圆角遮罩：滚动内容按弹窗圆角裁剪
                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: builtinList.width
                        height: builtinList.height
                        radius: DTK.platformTheme.windowRadius
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: builtinVScrollBar
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                delegate: Rectangle {
                    required property string widgetId
                    required property string name
                    required property string icon
                    required property int cols
                    required property int rows
                    required property bool builtin
                    required property bool installed

                    // 叠加式滚动条出现时为其让出宽度，避免遮盖行右缘
                    //（无循环：滚动条可见性只取决于内容高与视口高）
                    width: builtinList.width
                        - (builtinVScrollBar.visible ? builtinVScrollBar.width + 4 : 0)
                    height: 44
                    radius: DTK.platformTheme.windowRadius
                    color: addHover.containsMouse
                        ? Qt.rgba(0, 0, 0, 0.08) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            source: icon
                            sourceSize.width: 24
                            sourceSize.height: 24
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: name
                            font: DTK.fontManager.t6
                            elide: Text.ElideRight
                            color: palette.windowText
                            // 组件名截断时悬停显示全文
                            Components.ElideTip { anchors.fill: parent }
                        }

                        Text {
                            text: cols + "×" + rows
                            font: DTK.fontManager.t7
                            color: palette.windowText
                            opacity: 0.6
                        }

                        // 添加 / 已添加 按钮
                        Rectangle {
                            id: addBtnArea
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 26
                            radius: DTK.platformTheme.windowRadius
                            color: installed ? "transparent" : (addHover.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.06))

                            Text {
                                anchors.centerIn: parent
                                text: installed ? qsTr("Added") : qsTr("Add")
                                font: DTK.fontManager.t7
                                color: installed ? palette.windowText : palette.highlight
                            }

                            MouseArea {
                                id: addHover
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !installed
                                onClicked: {
                                    // 网络同意门控：首次添加声明 requiresNetwork 的组件时
                                    // 先弹协议弹窗（记录待添加组件，不立即添加）；同意后
                                    // 全局落盘并执行本次添加，未声明/已同意则直接添加
                                    if (Panel.widgetManager.widgetRequiresNetwork(widgetId)
                                            && !Panel.networkConsentGranted) {
                                        control.pendingNetworkWidgetId = widgetId
                                        networkConsentDialog.open()
                                    } else {
                                        Panel.widgetManager.addWidget(widgetId)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ===== 分区：已添加小组件 =====
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: qsTr("Added widgets")
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.7
            }

            ListView {
                id: addedList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 120
                clip: true
                spacing: 4
                model: control.instanceIds

                // 系统圆角遮罩：滚动内容按弹窗圆角裁剪
                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: addedList.width
                        height: addedList.height
                        radius: DTK.platformTheme.windowRadius
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: addedVScrollBar
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                delegate: Rectangle {
                    required property string modelData

                    // 叠加式滚动条出现时为其让出宽度，避免遮盖行右缘
                    //（无循环：滚动条可见性只取决于内容高与视口高）
                    width: addedList.width
                        - (addedVScrollBar.visible ? addedVScrollBar.width + 4 : 0)
                    height: 40
                    radius: DTK.platformTheme.windowRadius
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: Panel.widgetManager.displayName(
                                Panel.widgetManager.instanceWidgetId(modelData))
                            font: DTK.fontManager.t6
                            elide: Text.ElideRight
                            color: palette.windowText
                            // 实例名截断时悬停显示全文
                            Components.ElideTip { anchors.fill: parent }
                        }

                        // 第三方小组件：卸载（删除包）；内置不显示
                        Button {
                            visible: !Panel.widgetManager.isBuiltin(
                                Panel.widgetManager.instanceWidgetId(modelData))
                            text: qsTr("Uninstall")
                            font: DTK.fontManager.t7
                            implicitHeight: 24
                            onClicked: Panel.widgetManager.uninstallWidget(
                                Panel.widgetManager.instanceWidgetId(modelData))
                        }

                        // 移除实例（内置/第三方均可从面板移除）
                        Button {
                            text: qsTr("Remove")
                            font: DTK.fontManager.t7
                            implicitHeight: 24
                            onClicked: Panel.widgetManager.removeInstance(modelData)
                        }
                    }
                }
            }

            // ===== 底部：操作状态 + 从 .dwpkg 文件安装 =====
            Text {
                Layout.fillWidth: true
                visible: control.statusText.length > 0
                text: control.statusText
                font: DTK.fontManager.t7
                // 注：QQuickPalette 无 negativeText 角色，错误色用显式颜色
                color: control.statusError
                    ? (DTK.themeType === ApplicationHelper.DarkType
                        ? Qt.rgba(1, 0.45, 0.45, 1) : Qt.rgba(0.8, 0.2, 0.2, 1))
                    : palette.windowText
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                // 状态文案截断时悬停显示全文
                Components.ElideTip { anchors.fill: parent }
            }

            Button {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: qsTr("Install from .dwpkg file…")
                icon.name: "document-open"
                onClicked: fileDialog.open()
            }
        }

        FileDialog {
            id: fileDialog
            title: qsTr("Select a widget package")
            nameFilters: [qsTr("Widget packages") + " (*.dwpkg *.tar.xz)"]
            onAccepted: {
                if (Panel.widgetManager.installFromFile(selectedFile)) {
                    control.showStatus(qsTr("Widget installed"), false)
                } else {
                    control.showStatus(qsTr("Install failed: invalid or unsafe package"), true)
                }
            }
        }

        // 网络服务提示弹窗：首次添加声明 requiresNetwork 的组件时弹出。
        // 同意 → 写 DConfig（全局一次，重启保留）并立即执行本次添加；
        // 不同意/Esc/点击外部关闭 = 不添加、不写配置，停留添加面板。
        Popup {
            id: networkConsentDialog
            anchors.centerIn: parent
            width: parent.width - 40
            modal: true
            dim: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            padding: 16

            onClosed: control.pendingNetworkWidgetId = ""

            background: Rectangle {
                radius: DTK.platformTheme.windowRadius
                color: palette.window
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.15)
            }

            contentItem: ColumnLayout {
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Network Services Notice")
                    font: DTK.fontManager.t5
                    color: palette.windowText
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("This type of card fetches online content from third-party services (such as Bing wallpapers) through the panel's network proxy. After you agree, cards in the panel that use the network can fetch content online.")
                    font: DTK.fontManager.t6
                    color: palette.windowText
                    opacity: 0.8
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: qsTr("Decline")
                        onClicked: networkConsentDialog.close()
                    }

                    Button {
                        text: qsTr("Agree & Add")
                        onClicked: {
                            // 全局同意一次（DConfig 落盘，重启保留），随后立即添加本次组件
                            Panel.networkConsentGranted = true
                            if (control.pendingNetworkWidgetId.length > 0)
                                Panel.widgetManager.addWidget(control.pendingNetworkWidgetId)
                            networkConsentDialog.close()
                        }
                    }
                }
            }
        }
    }
}
