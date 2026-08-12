// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.dtk.style 1.0 as DStyle
import org.deepin.ds 1.0

Window {
    id: root

    // 获取 dock 所在的屏幕，侧栏跟随该屏幕显示
    function getDockScreen() {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet) {
            return Qt.application.screens[0]
        }

        let dockScreenName = dockApplet.screenName

        for (let i = 0; i < Qt.application.screens.length; i++) {
            if (Qt.application.screens[i].name === dockScreenName) {
                return Qt.application.screens[i]
            }
        }

        return Qt.application.screens[0]
    }

    // 与通知中心一致的尺寸：内容宽 360 + 左右各 10 padding
    property int contentPadding: 10
    property int contentWidth: 360

    visible: Panel.visible
    flags: Qt.Tool | Qt.FramelessWindowHint
    // X11 下 dde-shell 的 LayerShellEmulation 在 LayerButtom 分支会用 setFlags() 整体替换窗口 flags
    // （清掉 Qt.Tool/Qt.FramelessWindowHint），且窗口重建后窗口类型属性丢失，都会让面板回落为
    // 普通窗口被 kwin 装饰出标题栏与窗口按钮；在 C++ 处理之后按当前 layer 恢复 flags，
    // 置底时保留 WindowStaysOnBottomHint，收起/展开后同样兜底。
    // 注：QWindow::flags 无 NOTIFY 信号，onFlagsChanged 不会被调用，
    // 因此用 layer 变化、visible 变化与 Component.onCompleted 三个触发点恢复 flags。
    property bool layerIsBottom: DLayerShellWindow.layer === DLayerShellWindow.LayerButtom
    onLayerIsBottomChanged: {
        if (Qt.platform.pluginName === "xcb") {
            applyLayerFlags()
        }
    }
    onVisibleChanged: {
        if (visible && Qt.platform.pluginName === "xcb") {
            applyLayerFlags()
        }
    }
    Component.onCompleted: {
        if (Qt.platform.pluginName === "xcb") {
            applyLayerFlags()
        }
    }
    function applyLayerFlags() {
        root.flags = layerIsBottom
            ? Qt.WindowStaysOnBottomHint | Qt.Tool | Qt.FramelessWindowHint
            : Qt.Tool | Qt.FramelessWindowHint
    }
    width: contentWidth + contentPadding * 2

    // 置顶：Overlay 层（在所有窗口之上）；置底：Buttom 层（可被普通窗口覆盖）
    DLayerShellWindow.layer: Panel.pinned
        ? DLayerShellWindow.LayerOverlay : DLayerShellWindow.LayerButtom
    DLayerShellWindow.anchors: DLayerShellWindow.AnchorRight
        | DLayerShellWindow.AnchorTop | DLayerShellWindow.AnchorBottom
    DLayerShellWindow.topMargin: contentPadding
    DLayerShellWindow.rightMargin: contentPadding
    DLayerShellWindow.bottomMargin: contentPadding
    DLayerShellWindow.keyboardInteractivity: DLayerShellWindow.KeyboardInteractivityOnDemand

    palette: DTK.palette
    ColorSelector.family: Palette.CrystalColor

    DWindow.windowRadius: DTK.platformTheme.windowRadius
    DWindow.enableSystemResize: false
    DWindow.enableSystemMove: false
    DWindow.enabled: true
    color: "transparent"
    DWindow.enableBlurWindow: true
    DWindow.borderColor: DTK.themeType === ApplicationHelper.DarkType
        ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.06)

    screen: getDockScreen()
    onScreenChanged: {
        root.screen = Qt.binding(function () { return getDockScreen() })
    }

    function blendColorAlpha(fallback) {
        var appearance = DS.applet("org.deepin.ds.dde-appearance")
        if (!appearance || appearance.opacity < 0)
            return fallback
        return Math.max(appearance.opacity, 0.4)
    }

    StyledBehindWindowBlur {
        InsideBoxBorder {
            anchors.fill: parent
            radius: DTK.platformTheme.windowRadius
            color: DTK.themeType === ApplicationHelper.DarkType ?
                Qt.rgba(1, 1, 1, 0.1) :
                Qt.rgba(0, 0, 0, 0.1)
        }
        control: parent
        anchors.fill: parent
        cornerRadius: 0
        blendColor: {
            if (valid) {
                return DStyle.Style.control.selectColor(undefined,
                                                    Qt.rgba(238 / 255.0, 238 / 255.0, 238 / 255.0, blendColorAlpha(0.8)),
                                                    Qt.rgba(20 / 255, 20 / 255, 20 / 255, blendColorAlpha(0.8)))
            }
            return DStyle.Style.control.selectColor(undefined,
                                                DStyle.Style.behindWindowBlur.lightNoBlurColor,
                                                DStyle.Style.behindWindowBlur.darkNoBlurColor)
        }
    }

    Item {
        id: view
        anchors {
            top: parent.top
            topMargin: contentPadding
            left: parent.left
            leftMargin: contentPadding
            right: parent.right
            rightMargin: contentPadding
            bottom: parent.bottom
            bottomMargin: contentPadding
        }

        // 标题栏：标题 + 右上角置顶按钮（与通知中心标题栏同尺寸规范）
        RowLayout {
            id: header
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: 40
            spacing: 8

            Item {
                Layout.alignment: Qt.AlignLeft
                Layout.leftMargin: 18
                Layout.fillWidth: true
                implicitHeight: titleText.implicitHeight

                Text {
                    id: titleText
                    text: qsTr("Widget Toolbar")
                    font: DTK.fontManager.t4
                    elide: Text.ElideRight
                    color: palette.windowText
                }
            }

            PinButton {
                Layout.alignment: Qt.AlignRight
                pinned: Panel.pinned
                onPinnedChanged: Panel.pinned = pinned
            }
        }

        // 内容区占位（后续阶段放置小组件）
        Text {
            anchors.centerIn: parent
            text: qsTr("No widgets yet")
            font: DTK.fontManager.t5
            color: palette.windowText
            opacity: 0.6
        }
    }
}
