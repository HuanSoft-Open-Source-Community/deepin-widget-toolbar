// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.ds 1.0

// 面板与任务栏之间的间距计算（原 main.qml 中的边距逻辑）：
// 动态跟随任务栏位置——dock 在底部→面板在其上方、顶部→面板在其下方、
// 右侧→面板整体左移（dock 在其它屏幕时不处理）。
//
// 分工（两段式，缺一不可）：
//  1) dock applet 对象由本组件的有界轮询"取得"。DS.applet() 是函数调用，其返回值
//     不是 QML 可跟踪依赖，只有拿到对象、赋给 dockApplet 属性，下游才有可挂钩的东西；
//  2) 三条边距写成读该对象 Q_PROPERTY 的**绑定**。position / screenName /
//     frontendWindowRect 都是带 NOTIFY 的属性（实测 org.deepin.ds.dock.so 的
//     moc 符号有 positionChanged/screenNameChanged/frontendWindowRectChanged），
//     QML 求值绑定时会捕获函数体内对这些属性的读取，任务栏一有变化即自动重算。
// 故本组件不再常驻轮询：取得对象后即静默，边距的后续更新全靠绑定跟踪。
// C++ 端 WindowGuard 监听 DLayerShellWindow::marginsChanged 重放锚定几何，
// 边距变则面板变——面板**显示中**调整任务栏同样自适应，无需隐藏再显示
// （旧实现把边距当命令式赋值、且轮询在边距稳定后 1 拍即停，正是该回归的根因）。
// 根必须是 Item（QtObject 无 default property，无法容纳 Timer 子对象）。
Item {
    id: root
    visible: false

    // 主面板注入：当前屏幕（root.screen）
    property var screenRef: null
    // 与任务栏之间的间距与其他边缘一致（contentPadding），不再额外追加：
    // 面板距 dock 的空隙 = 距屏幕其他边缘的空隙，视觉对称。
    property int contentPadding: 10

    // dock applet 对象缓存（DS.applet("org.deepin.ds.dock") 的返回值，实际类型是
    // dock 自己的面板类，frontendWindowRect/position/screenName 都挂在它身上）。
    // null = 尚未取得，此时三条边距按 0 计（外加 contentPadding 下限）。
    property var dockApplet: null

    // 三条边距的下限恒为 contentPadding（desiredMargin = layerShellMargin + contentPadding），
    // 0 从来不是合法值：绑定首次求值即得 contentPadding，保证主面板 DLayerShellWindow
    // 绑定首次求值即非 0——否则窗口首次映射（visible 绑定先于边距绑定求值）会以 0 边距
    // 计算几何，X11 模拟层把面板拉满全高（上下边距视觉为 0）。
    readonly property int topMargin: desiredMargin(0)
    readonly property int rightMargin: desiredMargin(1)
    readonly property int bottomMargin: desiredMargin(2)

    // dock 位置枚举与 dde-shell dock 一致：0=Top 1=Right 2=Bottom 3=Left。
    // applet 必须作为参数显式传入：在函数体内读它的属性即建立本绑定的依赖，
    // 若在这里再调 DS.applet() 就又变成不可跟踪的了。
    function windowMargin(applet, position) {
        if (!applet) {
            return 0
        }

        // dock 代理属性可能晚于窗口创建就绪（值为 undefined/null）：
        // 全部判空后返回 0，避免任何属性访问抛 TypeError 导致绑定被禁用
        // （绑定一旦禁用永不恢复，边距停在旧值、面板被拉满全高）。
        let dockScreen = applet.screenName
        if (typeof dockScreen !== "string" || dockScreen.length === 0) {
            return 0
        }
        if (!root.screenRef) {
            return 0
        }
        if (dockScreen !== root.screenRef.name) {
            return 0
        }

        let dockPosition = applet.position
        if (typeof dockPosition !== "number" || dockPosition !== position) {
            return 0
        }

        // frontendWindowRect 为物理像素，除以 dpr 得到逻辑尺寸
        let frontendRect = applet.frontendWindowRect
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
        return windowMargin(root.dockApplet, position)
    }

    // dock 数据是否已可用于边距计算。只用于判定"轮询可以停了"：对象与属性
    // 的有效性由绑定自己保证（属性变化即重算），不再需要轮询维持数值。
    function dockDataReady() {
        let applet = root.dockApplet
        if (!applet || typeof applet.screenName !== "string"
            || applet.screenName.length === 0 || !root.screenRef) {
            return false
        }
        if (applet.screenName !== root.screenRef.name) {
            return true
        }
        let frontendRect = applet.frontendWindowRect
        if (!frontendRect
            || typeof frontendRect.x !== "number"
            || typeof frontendRect.y !== "number"
            || typeof frontendRect.width !== "number"
            || typeof frontendRect.height !== "number") {
            return false
        }
        return true
    }

    // 取整显式化：dock 矩形除以 dpr 是非整数，边距属性为 int
    function desiredMargin(position) {
        return Math.round(layerShellMargin(position) + root.contentPadding)
    }

    // 取得（或换血后重取）dock applet 对象：仅在身份变化时赋值，避免无谓的
    // 绑定重算；赋值即让三条边距绑定改挂到新对象的 NOTIFY 上。
    function acquireDockApplet() {
        const applet = DS.applet("org.deepin.ds.dock")
        if (applet !== root.dockApplet) {
            root.dockApplet = applet
        }
    }

    // 窗口显示/重建后调用：重新取得对象并重启**有界**轮询，直到 dock 数据可用
    // （最多约 10s 后静默）。轮询只为取得对象与等其属性就绪，数值更新由绑定负责。
    property int marginAcquireTicks: 0
    function restart() {
        acquireDockApplet()
        marginAcquireTicks = 0
        marginAcquireTimer.restart()
    }

    Timer {
        id: marginAcquireTimer
        interval: 250
        repeat: true
        onTriggered: {
            root.marginAcquireTicks++
            if (root.marginAcquireTicks > 40) {
                stop()
                return
            }
            root.acquireDockApplet()
            if (root.dockDataReady()) {
                stop()
            }
        }
    }

    // 子组件先于父组件（主面板 Window）完成：这里先取一次对象，让边距绑定在
    // 主面板 onCompleted 之前就挂上 dock 属性，不依赖调用方的 restart() 纪律。
    Component.onCompleted: {
        root.acquireDockApplet()
    }
}
