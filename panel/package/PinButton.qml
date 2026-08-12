// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0

// 置顶/置底切换按钮：DTK 按钮 + 自绘图钉图标（文件资源，随 package 分发）
// 图标经 ColorOverlay 按主题前景色着色，亮暗主题自适应
ToolButton {
    id: root

    property bool pinned: false

    implicitWidth: 36
    implicitHeight: 36

    contentItem: Item {
        Image {
            id: iconImage
            anchors.centerIn: parent
            source: Qt.resolvedUrl(root.pinned ? "icons/pin.svg" : "icons/unpin.svg")
            sourceSize: Qt.size(20, 20)
            visible: false
        }
        ColorOverlay {
            anchors.fill: iconImage
            source: iconImage
            color: palette.windowText
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: text

    ToolTip.visible: hovered
    ToolTip.delay: 500
    ToolTip.text: pinned ? qsTr("Unpin") : qsTr("Pin to top")

    onClicked: pinned = !pinned
}
