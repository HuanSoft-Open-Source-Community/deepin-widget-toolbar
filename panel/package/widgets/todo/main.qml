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

    widgetConfig: ({})
    dataDir: ""
    instanceId: ""

    property string notePath: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId + ".txt" : ""
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 卡片底色跟随内容背景色，让内容自定义色延伸到整个便签卡片
    backgroundColor: root.contentBackgroundColor
    textColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.textColor, "#3d2b00")
    property color titleBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.titleBackgroundColor, "#c8a500")
    property color titleTextColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.titleTextColor, "#1a1a00")
    property color contentBackgroundColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.contentBackgroundColor, "#fff8d6")
    property color lineColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.lineColor, "#cccccc")
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
    // 行底线必须与 TextArea 实际文本行高一致，不能用像素大小的经验倍率估算
    property real lineHeight: Math.max(12, noteFontMetrics.lineSpacing)
    property int autoSaveInterval: widgetConfig && widgetConfig.autoSaveInterval
        ? Number(widgetConfig.autoSaveInterval) : 5000

    onNotePixelSizeChanged: if (lineCanvas) lineCanvas.requestPaint()
    onLineHeightChanged: if (lineCanvas) lineCanvas.requestPaint()

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

        Rectangle {
            id: titleBar
            width: parent.width
            height: root.titlePixelSize + 8
            radius: 4
            color: root.transparentBackground ? "transparent" : root.titleBackgroundColor

            Text {
                anchors.centerIn: parent
                text: qsTr("Sticky Note")
                font.pixelSize: root.titlePixelSize
                color: root.titleTextColor
            }
        }

        Item {
            width: parent.width
            height: parent.height - titleBar.height - content.spacing

            Rectangle {
                anchors.fill: parent
                radius: DTK.platformTheme.windowRadius
                color: root.transparentBackground ? "transparent" : root.contentBackgroundColor
            }

            TextArea {
                id: noteArea
                anchors.fill: parent
                font.pixelSize: root.notePixelSize
                color: root.textColor
                placeholderText: qsTr("Write something…")
                FontMetrics {
                    id: noteFontMetrics
                    font: noteArea.font
                }
                background: Canvas {
                    id: lineCanvas
                    anchors.fill: parent

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        if (!ctx)
                            return
                        ctx.reset()
                        ctx.strokeStyle = root.transparentBackground ? "transparent" : root.lineColor
                        ctx.globalAlpha = 0.7
                        ctx.lineWidth = 1

                        var y = noteArea.topPadding + root.lineHeight - 1
                        while (y < height - noteArea.bottomPadding) {
                            ctx.beginPath()
                            ctx.moveTo(2, y)
                            ctx.lineTo(width - 4, y)
                            ctx.stroke()
                            y += root.lineHeight
                        }
                    }
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
}
