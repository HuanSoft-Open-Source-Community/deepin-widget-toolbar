// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.dtk.style 1.0 as DStyle
import org.deepin.ds 1.0

// 添加小组件弹出面板：
//  - 基于 PanelPopup（DPanel 辅助窗口）：无 Qt 窗口标题、失焦自动关闭、跟随主窗口定位
//  - 与侧栏一致的透明毛玻璃风格（PopupWindow 自带 StyledBehindWindowBlur + 系统圆角）
//  - 右上角圆形叉号关闭
//  - 内置小组件可添加；已添加实例可移除；第三方小组件可卸载（内置不可卸载）
PanelPopup {
    id: control

    // 弹在侧栏面板左侧，顶部对齐
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

                ScrollBar.vertical: ScrollBar {
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

                    width: builtinList.width
                    height: 44
                    radius: DTK.platformTheme.windowRadius
                    color: addHover.containsMouse || addBtnArea.containsMouse
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
                        }

                        Text {
                            Layout.fillWidth: true
                            text: name
                            font: DTK.fontManager.t6
                            elide: Text.ElideRight
                            color: palette.windowText
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
                            color: installed ? "transparent" : (addBtnArea.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.06))

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
                                onClicked: Panel.widgetManager.addWidget(widgetId)
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

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                delegate: Rectangle {
                    required property string modelData

                    width: addedList.width
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
    }
}
