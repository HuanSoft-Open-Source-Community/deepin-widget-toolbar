// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// 设置弹出面板（与添加小组件面板同框架）：
//  - 基于 PanelPopup（DPanel 辅助窗口）：无 Qt 窗口标题、失焦自动关闭、跟随主窗口定位
//  - 面板显示与置顶两项，直接写回 Panel 属性（经 DConfig 持久化）
PanelPopup {
    id: control

    // 弹在侧栏面板左侧，顶部对齐
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-settings"

    width: 320
    height: 200

    // 右上角圆形叉号关闭按钮
    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // ===== 标题栏：标题 + 圆形叉号 =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: qsTr("Settings")
                    font: DTK.fontManager.t4
                    elide: Text.ElideRight
                    color: palette.windowText
                }

                Rectangle {
                    id: closeBtn
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: width / 2
                    color: closeBtnArea.pressed
                        ? Qt.rgba(0, 0, 0, 0.15)
                        : closeBtnArea.containsMouse ? Qt.rgba(0, 0, 0, 0.1) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 12
                        color: palette.windowText
                    }

                    MouseArea {
                        id: closeBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: control.close()
                    }
                }
            }

            // ===== 设置项 =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Show panel")
                    font: DTK.fontManager.t6
                    color: palette.windowText
                }

                Switch {
                    checked: Panel.visible
                    onToggled: Panel.visible = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Pin to top")
                    font: DTK.fontManager.t6
                    color: palette.windowText
                }

                Switch {
                    checked: Panel.pinned
                    onToggled: Panel.pinned = checked
                }
            }
        }
    }
}
