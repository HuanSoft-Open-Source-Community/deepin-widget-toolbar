// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 内置示例小组件：便签（默认 2×2）
// 实例数据持久化演示：写入 dataDir/<instanceId>.txt（宿主隔离的实例数据目录）
Item {
    id: root

    // 由宿主 Loader 注入的实例上下文
    property string dataDir: ""
    property string instanceId: ""

    property string notePath: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId + ".txt" : ""

    // 注入属性就绪（notePath 变化）后加载已保存内容
    onNotePathChanged: {
        Qt.callLater(function () {
            if (noteArea)
                noteArea.loadNote()
        })
    }

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    Column {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Text {
            text: qsTr("Sticky Note")
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        TextArea {
            id: noteArea
            width: parent.width
            height: parent.height - 30
            font: DTK.fontManager.t7
            color: palette.windowText
            placeholderText: qsTr("Write something…")
            background: Rectangle {
                radius: DTK.platformTheme.windowRadius
                color: "transparent"
            }

            // 注入的 dataDir/instanceId 变化时加载（晚于 Component.onCompleted，
            // 因此不能依赖 onCompleted 读取）
            function loadNote() {
                if (root.notePath.length > 0 && FileIO.exists(root.notePath))
                    noteArea.text = FileIO.readTextFile(root.notePath)
            }
            function saveNote() {
                if (root.notePath.length > 0)
                    FileIO.writeTextFile(root.notePath, text)
            }

            // 失焦与销毁时保存（销毁时保存可避免实例被移除/重建导致输入丢失）
            onActiveFocusChanged: {
                if (!activeFocus)
                    saveNote()
            }
            Component.onDestruction: saveNote()

            // 定时兜底保存（防长时间未失焦导致数据丢失）
            Timer {
                id: autoSaveTimer
                interval: 5000
                repeat: true
                running: noteArea.activeFocus
                onTriggered: noteArea.saveNote()
            }
        }
    }
}
