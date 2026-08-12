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

    // 动态跟随任务栏位置：面板与任务栏在 上/右/下 三边保持 contentPadding 间距
    // （dock 在底部→面板在其上方、顶部→面板在其下方、右侧→面板整体左移；dock 在其它屏幕时不处理）
    // dock 位置枚举与 dde-shell dock 一致：0=Top 1=Right 2=Bottom 3=Left
    function windowMargin(position) {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet) {
            return 0
        }

        let dockScreen = dockApplet.screenName
        let screen = root.screen.name
        if (dockScreen !== screen) {
            return 0
        }

        let dockPosition = dockApplet.position
        if (dockPosition !== position) {
            return 0
        }

        // frontendWindowRect 为物理像素，除以 dpr 得到逻辑尺寸
        let frontendRect = dockApplet.frontendWindowRect
        if (!frontendRect) {
            return 0
        }
        let dpr = root.screen.devicePixelRatio
        let dockGeometry = Qt.rect(
            frontendRect.x / dpr,
            frontendRect.y / dpr,
            frontendRect.width / dpr,
            frontendRect.height / dpr
        )

        let screenGeometry = Qt.rect(
            root.screen.virtualX,
            root.screen.virtualY,
            root.screen.width,
            root.screen.height
        )

        switch (position) {
            case 0: { // DOCK_TOP：面板在任务栏下方留间距
                let visibleHeight = Math.max(0, dockGeometry.y + dockGeometry.height - screenGeometry.y)
                return Math.min(visibleHeight, dockGeometry.height)
            }
            case 1: { // DOCK_RIGHT：面板整体左移
                let visibleWidth = Math.max(0, screenGeometry.x + screenGeometry.width - dockGeometry.x)
                return Math.min(visibleWidth, dockGeometry.width)
            }
            case 2: { // DOCK_BOTTOM：面板在任务栏上方留间距
                let visibleHeight = Math.max(0, screenGeometry.y + screenGeometry.height - dockGeometry.y)
                return Math.min(visibleHeight, dockGeometry.height)
            }
        }
        // dock 在左侧（position=3）或未知位置：面板在屏幕右侧不与任务栏重叠，无需处理
        return 0
    }

    // Wayland 下任务栏自身通过 exclusionZone 排布可用区域，与通知中心一致不额外处理
    function layerShellMargin(position) {
        if (Qt.platform.pluginName === "wayland") {
            return 0
        }
        return windowMargin(position)
    }

    // 与任务栏之间的额外间距：仅当 dock 与面板同屏且位于该边时生效（X11/Wayland 通用）
    function dockSpacingFor(position) {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet) {
            return 0
        }
        if (dockApplet.screenName !== root.screen.name) {
            return 0
        }
        if (dockApplet.position !== position) {
            return 0
        }
        return dockSpacing
    }

    // 与通知中心一致的尺寸：内容宽 360 + 左右各 10 padding
    property int contentPadding: 10
    property int contentWidth: 360
    // 侧栏与任务栏之间的间距（在 contentPadding 之外额外追加）
    property int dockSpacing: 20

    visible: Panel.visible
    flags: Qt.Tool | Qt.FramelessWindowHint
    // X11 下 dde-shell 的 LayerShellEmulation 在 LayerButtom 分支会用 setFlags() 整体替换窗口 flags
    // （清掉 Qt.Tool/Qt.FramelessWindowHint），且窗口重建后窗口类型属性丢失，都会让面板回落为
    // 普通窗口被 kwin 装饰出标题栏与窗口按钮。主兜底在 C++ 端（WidgetToolbarPanel 的事件过滤器
    // 与 layerChanged 监听，覆盖窗口重建/显示/曝光时机），这里再按 layer/visible 变化与初始化
    // 时恢复一次作为辅助，置底时保留 WindowStaysOnBottomHint，收起/展开后同样兜底。
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
    // 置底时收缩桌面工作区一个面板宽度，桌面图标等自动避开面板区域；
    // strut/exclusive zone 不影响背景层，桌面背景图保持全屏不变
    DLayerShellWindow.exclusionZone: Panel.pinned ? 0 : root.width
    DLayerShellWindow.anchors: DLayerShellWindow.AnchorRight
        | DLayerShellWindow.AnchorTop | DLayerShellWindow.AnchorBottom
    DLayerShellWindow.topMargin: layerShellMargin(0) + contentPadding + dockSpacingFor(0)
    DLayerShellWindow.rightMargin: layerShellMargin(1) + contentPadding + dockSpacingFor(1)
    DLayerShellWindow.bottomMargin: layerShellMargin(2) + contentPadding + dockSpacingFor(2)
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
        // 与任务栏（dock）一致：直接使用 dde-appearance 的透明度，不做下限钳制，
        // 保证面板透明度随任务栏透明度同步变化
        return appearance.opacity
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
