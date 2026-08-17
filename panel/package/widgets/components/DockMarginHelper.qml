// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.ds 1.0

// 面板与任务栏之间的间距计算与轮询（原 main.qml 中的边距逻辑）：
// 动态跟随任务栏位置——dock 在底部→面板在其上方、顶部→面板在其下方、
// 右侧→面板整体左移（dock 在其它屏幕时不处理）。
// DS.applet() 的返回值不是 QML 可跟踪依赖，只能靠轮询重绑感知就绪时机，
// 因此本组件持有轮询 Timer，输出 topMargin/rightMargin/bottomMargin 属性，
// 主面板以绑定消费；窗口显示/重建后调用 restart() 重启轮询。
// 根必须是 Item（QtObject 无 default property，无法容纳 Timer 子对象）。
Item {
    id: root
    visible: false

    // 主面板注入：当前屏幕（root.screen）
    property var screenRef: null
    // 与任务栏之间的间距与其他边缘一致（contentPadding），不再额外追加：
    // 面板距 dock 的空隙 = 距屏幕其他边缘的空隙，视觉对称。
    property int contentPadding: 10

    property int topMargin: 0
    property int rightMargin: 0
    property int bottomMargin: 0

    // dock 位置枚举与 dde-shell dock 一致：0=Top 1=Right 2=Bottom 3=Left
    function windowMargin(position) {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet) {
            return 0
        }

        // dock 代理属性可能晚于窗口创建就绪（值为 undefined/null）：
        // 全部判空后返回 0，避免任何属性访问抛 TypeError 导致绑定被禁用
        // （绑定禁用后 margin 永不更新、面板被拉满全高）。
        let dockScreen = dockApplet.screenName
        if (typeof dockScreen !== "string" || dockScreen.length === 0) {
            return 0
        }
        if (!root.screenRef) {
            return 0
        }
        if (dockScreen !== root.screenRef.name) {
            return 0
        }

        let dockPosition = dockApplet.position
        if (typeof dockPosition !== "number" || dockPosition !== position) {
            return 0
        }

        // frontendWindowRect 为物理像素，除以 dpr 得到逻辑尺寸
        let frontendRect = dockApplet.frontendWindowRect
        if (!frontendRect
            || typeof frontendRect.x !== "number"
            || typeof frontendRect.y !== "number"
            || typeof frontendRect.width !== "number"
            || typeof frontendRect.height !== "number") {
            return 0
        }
        let dpr = root.screenRef.devicePixelRatio
        let dockGeometry = Qt.rect(
            frontendRect.x / dpr,
            frontendRect.y / dpr,
            frontendRect.width / dpr,
            frontendRect.height / dpr
        )

        let screenGeometry = Qt.rect(
            root.screenRef.virtualX,
            root.screenRef.virtualY,
            root.screenRef.width,
            root.screenRef.height
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

    // dock 数据是否已可用于边距计算。DS.applet() 的返回值不是 QML 可跟踪依赖，
    // 只能靠轮询重绑感知就绪时机；dock 在其它屏幕时也算就绪（无需继续等待）。
    function dockDataReady() {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet || typeof dockApplet.screenName !== "string"
            || dockApplet.screenName.length === 0 || !root.screenRef) {
            return false
        }
        if (dockApplet.screenName !== root.screenRef.name) {
            return true
        }
        let frontendRect = dockApplet.frontendWindowRect
        if (!frontendRect
            || typeof frontendRect.x !== "number"
            || typeof frontendRect.y !== "number"
            || typeof frontendRect.width !== "number"
            || typeof frontendRect.height !== "number") {
            return false
        }
        return true
    }

    function desiredMargin(position) {
        return layerShellMargin(position) + contentPadding
    }

    // 直接赋值三条 margin 属性：值不变时 setter 无操作，变化时触发
    // marginsChanged 供主面板的 DLayerShellWindow 绑定更新。
    function refresh() {
        root.topMargin = desiredMargin(0)
        root.rightMargin = desiredMargin(1)
        root.bottomMargin = desiredMargin(2)
    }

    // 窗口显示/重建后调用：立即刷新并重启轮询，直到 dock 数据就绪且
    // 边距连续两次稳定（最多约 10s，之后静默保留当前边距）。
    property int marginRefreshTicks: 0
    function restart() {
        refresh()
        marginRefreshTicks = 0
        marginRefreshTimer.restart()
    }

    Timer {
        id: marginRefreshTimer
        interval: 250
        repeat: true
        onTriggered: {
            root.marginRefreshTicks++
            if (root.marginRefreshTicks > 40) {
                stop()
                return
            }
            const beforeTop = root.topMargin
            const beforeRight = root.rightMargin
            const beforeBottom = root.bottomMargin
            root.refresh()
            if (root.dockDataReady()
                && root.topMargin === beforeTop
                && root.rightMargin === beforeRight
                && root.bottomMargin === beforeBottom) {
                stop()
            }
        }
    }
}
