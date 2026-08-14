// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0

// 添加/设置/关于/组件配置面板共用的标题栏：标题 + 圆形关闭按钮。
RowLayout {
    id: root

    property string title: ""
    signal closeRequested()

    Layout.fillWidth: true
    spacing: 8

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        text: root.title
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
            onClicked: root.closeRequested()
        }
    }
}
