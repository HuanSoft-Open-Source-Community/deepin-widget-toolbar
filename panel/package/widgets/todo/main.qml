// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置示例小组件：便签（默认 2×2）
// 实例数据持久化演示：写入 dataDir/<instanceId>.txt（宿主隔离的实例数据目录）
Components.WidgetCard {
    id: root

    property var widgetConfig: ({})
    property string dataDir: ""
    property string instanceId: ""

    property string notePath: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId + ".txt" : ""
    property int titlePixelSize: Math.max(10, Math.min(20, Math.round(content.width * 0.04)))
    property real noteFontScale: {
        var mode = widgetConfig && widgetConfig.noteFontScale ? widgetConfig.noteFontScale : "medium"
        if (mode === "small")
            return 0.85
        if (mode === "large")
            return 1.2
        return 1.0
    }
    property int notePixelSize: Math.max(9, Math.min(20,
        Math.round(content.height * 0.09 * noteFontScale)))
    property int autoSaveInterval: widgetConfig && widgetConfig.autoSaveInterval
        ? Number(widgetConfig.autoSaveInterval) : 5000

    onNotePathChanged: {
        Qt.callLater(function () {
            if (noteArea)
                noteArea.loadNote()
        })
    }

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        Text {
            text: qsTr("Sticky Note")
            font.pixelSize: root.titlePixelSize
            color: palette.windowText
        }

        TextArea {
            id: noteArea
            width: parent.width
            height: parent.height - 30
            font.pixelSize: root.notePixelSize
            color: palette.windowText
            placeholderText: qsTr("Write something…")
            background: Rectangle {
                radius: DTK.platformTheme.windowRadius
                color: "transparent"
            }

            function loadNote() {
                if (root.notePath.length > 0 && FileIO.exists(root.notePath))
                    noteArea.text = FileIO.readTextFile(root.notePath)
            }
            function saveNote() {
                if (root.notePath.length > 0)
                    FileIO.writeTextFile(root.notePath, text)
            }

            onActiveFocusChanged: {
                if (!activeFocus)
                    saveNote()
            }
            Component.onDestruction: saveNote()

            Timer {
                id: autoSaveTimer
                interval: root.autoSaveInterval
                repeat: true
                running: noteArea.activeFocus
                onTriggered: noteArea.saveNote()
            }
        }
    }
}
