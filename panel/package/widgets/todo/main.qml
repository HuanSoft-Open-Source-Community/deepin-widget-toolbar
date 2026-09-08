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

    // 主面板拖放层接收按下以持有鼠标抓取；普通点击由此转发，
    // 让便签仍能进入编辑并把光标放到点击位置。
    // 注意：X11 下面板是 Dock/Notification 类窗口，kwin 不因点击授予键盘
    // 焦点——只做 QML 取焦时光标会闪但按键到不了窗口。因此点击进入编辑
    // 时须随用户手势请求窗口激活（仅本组件点击触发，媒体按钮等普通点击
    // 不会借 handleHostClick 抢走其它应用的键盘焦点）。
    property point lastClickPos: Qt.point(0, 0)
    property string textAtClick: ""

    function focusNoteAt(x, y) {
        var p = noteArea.mapFromItem(root, x, y)
        noteArea.forceActiveFocus()
        var pos = noteArea.positionAt(p.x, p.y)
        noteArea.cursorPosition = Math.max(0, pos)
    }

    function handleHostClick(x, y) {
        WidgetHost.activateWindow()
        root.lastClickPos = Qt.point(x, y)
        root.textAtClick = noteArea.text
        focusNoteAt(x, y)
        // 窗口激活是异步的（X11 下 kwin 处理激活后才 FocusIn），期间窗口
        // 激活事件可能重置 QML 焦点；短暂重发取焦直到稳定（有界，3×150ms，
        // 用户一旦开始输入即停，不与按键抢光标）。
        focusRetry.left = 3
        focusRetry.restart()
    }

    Timer {
        id: focusRetry
        interval: 150
        repeat: true
        property int left: 0
        onTriggered: {
            if (left <= 0) {
                stop()
                return
            }
            --left
            if (noteArea.text !== root.textAtClick) {
                stop()
                return
            }
            root.focusNoteAt(root.lastClickPos.x, root.lastClickPos.y)
        }
    }

    // 标题区高度：透明模式为纯文字（配色模式前样式），无标题条占位
    property int titleBarHeight: root.effectiveTransparent
        ? root.titlePixelSize : root.titlePixelSize + 8

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        // 标题条：仅非透明模式显示
        Rectangle {
            id: titleBar
            width: parent.width
            height: root.titlePixelSize + 8
            radius: 4
            visible: !root.effectiveTransparent
            color: root.titleBackgroundColor

            Text {
                anchors.centerIn: parent
                text: qsTr("Sticky Note")
                font.pixelSize: root.titlePixelSize
                color: root.titleTextColor
            }
        }

        // 透明模式标题：配色模式前样式——无底色条，主题自适应文字
        Text {
            visible: root.effectiveTransparent
            text: qsTr("Sticky Note")
            font.pixelSize: root.titlePixelSize
            color: root.themeTextColor
        }

        Item {
            width: parent.width
            height: parent.height - root.titleBarHeight - content.spacing

            // 内容底色：仅非透明模式显示
            Rectangle {
                anchors.fill: parent
                radius: DTK.platformTheme.windowRadius
                visible: !root.effectiveTransparent
                color: root.contentBackgroundColor
            }

            TextArea {
                id: noteArea
                anchors.fill: parent
                font.pixelSize: root.notePixelSize
                color: root.effectiveTransparent ? root.themeTextColor : root.textColor
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
                        // 透明模式为配色模式前样式：无行底线
                        if (root.effectiveTransparent)
                            return
                        ctx.reset()
                        ctx.strokeStyle = root.lineColor
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
