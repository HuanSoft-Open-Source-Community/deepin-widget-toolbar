// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// 完整控制三件套：上一曲/播放暂停/下一曲（播放器小组件拆分，中/宽/大共用）。
// 能力与状态由调用方注入；hover/press 高亮索引由调用方驱动
//（宿主拖放层拦截组件内部鼠标事件，交互状态由宿主回调更新）。
Item {
    id: root

    property int controlSize: 28
    property int controlSpacing: 14
    property int hoveredControl: -1
    property int pressedControl: -1
    property color hoverFill: Qt.rgba(1, 1, 1, 0.1)
    property color pressFill: Qt.rgba(1, 1, 1, 0.18)
    // 能力开关（由调用方绑定 MPRIS 能力）
    property bool canGoPrevious: false
    property bool canControl: false
    property bool canPlay: false
    property bool canPause: false
    property bool canGoNext: false
    // 播放状态（决定播放/暂停图标）
    property bool playing: false
    // 图标源（调用方按主题提供）
    property string prevIcon: ""
    property string playIcon: ""
    property string pauseIcon: ""
    property string nextIcon: ""

    width: root.controlSize * 3 + root.controlSpacing * 2
    height: root.controlSize

    Row {
        anchors.centerIn: parent
        spacing: root.controlSpacing

        Item {
            width: root.controlSize
            height: root.controlSize
            enabled: root.canGoPrevious
            opacity: enabled ? 1.0 : 0.3

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.pressedControl === 0 ? root.pressFill
                    : (root.hoveredControl === 0 ? root.hoverFill : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Image {
                anchors.fill: parent
                source: root.prevIcon
                sourceSize.width: root.controlSize
                sourceSize.height: root.controlSize
            }
        }

        Item {
            width: root.controlSize
            height: root.controlSize
            enabled: root.canControl && (root.canPlay || root.canPause)
            opacity: enabled ? 1.0 : 0.3

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.pressedControl === 1 ? root.pressFill
                    : (root.hoveredControl === 1 ? root.hoverFill : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Image {
                anchors.fill: parent
                source: root.playing ? root.pauseIcon : root.playIcon
                sourceSize.width: root.controlSize
                sourceSize.height: root.controlSize
            }
        }

        Item {
            width: root.controlSize
            height: root.controlSize
            enabled: root.canGoNext
            opacity: enabled ? 1.0 : 0.3

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.pressedControl === 2 ? root.pressFill
                    : (root.hoveredControl === 2 ? root.hoverFill : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Image {
                anchors.fill: parent
                source: root.nextIcon
                sourceSize.width: root.controlSize
                sourceSize.height: root.controlSize
            }
        }
    }
}
