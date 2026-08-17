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

        // dock 代理属性可能晚于窗口创建就绪（值为 undefined/null）：
        // 全部判空后返回 0，避免任何属性访问抛 TypeError 导致绑定被禁用
        // （绑定禁用后 margin 永不更新、面板被拉满全高）。
        let dockScreen = dockApplet.screenName
        if (typeof dockScreen !== "string" || dockScreen.length === 0) {
            return 0
        }
        if (!root.screen) {
            return 0
        }
        if (dockScreen !== root.screen.name) {
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

    // dock 数据是否已可用于边距计算。DS.applet() 的返回值不是 QML 可跟踪依赖，
    // 只能靠轮询重绑感知就绪时机；dock 在其它屏幕时也算就绪（无需继续等待）。
    function dockDataReady() {
        let dockApplet = DS.applet("org.deepin.ds.dock")
        if (!dockApplet || typeof dockApplet.screenName !== "string"
            || dockApplet.screenName.length === 0 || !root.screen) {
            return false
        }
        if (dockApplet.screenName !== root.screen.name) {
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

    // 与任务栏之间的间距与其他边缘一致（contentPadding），不再额外追加：
    // 面板距 dock 的空隙 = 距屏幕其他边缘的空隙，视觉对称。
    function blendColorAlpha(fallback) {
        var appearance = DS.applet("org.deepin.ds.dde-appearance")
        if (!appearance || appearance.opacity < 0)
            return fallback
        // 与任务栏（dock）一致：直接使用 dde-appearance 的透明度，不做下限钳制，
        // 保证面板透明度随任务栏透明度同步变化
        return appearance.opacity
    }

    // ===== 小组件网格 =====

    // 实例 ID 列表（由 C++ WidgetManager 维护，变化时刷新）
    property var instanceIds: Panel.widgetManager ? Panel.widgetManager.instanceIds() : []
    // 位置映射（instanceId → Qt.point）：仅位置变化时刷新，避免重建 Repeater 以保留动画
    property var gridPositions: ({})
    // 布局版本：位置变化时递增，驱动内容高度等绑定重新求值
    property int layoutVersion: 0
    property bool widgetsLoaded: false
    // 网格内容高度的动画代理：尺寸切换时滚动范围平滑过渡
    property int animatedGridContentHeight: Math.max(gridContentHeight(), height)
    Behavior on animatedGridContentHeight {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // 刷新实例 ID 列表：只有增删实例时才重建模型并重置滚动；
    // 尺寸切换只更新位置/尺寸映射，避免 Repeater 重建导致动画丢失。
    function refreshInstanceIds() {
        let ids = Panel.widgetManager.instanceIds()
        let changed = ids.length !== root.instanceIds.length
        if (!changed) {
            for (let i = 0; i < ids.length; ++i) {
                if (ids[i] !== root.instanceIds[i]) {
                    changed = true
                    break
                }
            }
        }
        if (changed) {
            root.instanceIds = ids
            gridFlickable.contentY = 0
        }
        root.updateGridPositions()
    }

    // 从 C++ 读取全部实例位置并刷新映射
    function updateGridPositions() {
        let positions = {}
        for (let i = 0; i < root.instanceIds.length; i++) {
            let id = root.instanceIds[i]
            positions[id] = Qt.point(
                Panel.widgetManager.instanceGridX(id),
                Panel.widgetManager.instanceGridY(id))
        }
        root.gridPositions = positions
        root.layoutVersion++
    }

    // 实例左上角像素坐标；位置映射未就绪时回退到 C++ 直接读取
    function cellX(instanceId) {
        let p = root.gridPositions[instanceId]
        return (p ? p.x : Panel.widgetManager.instanceGridX(instanceId)) * (cellWidth + cellSpacing)
    }
    function cellY(instanceId) {
        let p = root.gridPositions[instanceId]
        return (p ? p.y : Panel.widgetManager.instanceGridY(instanceId)) * (cellHeight + cellSpacing)
    }

    Connections {
        target: Panel.widgetManager
        function onInstancesChanged() {
            root.refreshInstanceIds()
        }
        function onLayoutChanged() {
            updateGridPositions()
        }
    }

    // 网格参数：横向固定 4 列，纵向无限行（滚动）
    property int gridColumns: 4
    property int cellSpacing: 8
    property int cellWidth: Math.floor((gridArea.width - (gridColumns - 1) * cellSpacing) / gridColumns)
    // 格子为正方形；2×2 小组件占 (2*cellWidth + spacing) 见方
    property int cellHeight: cellWidth

    // 网格内容总高度（由实例的最大 gridY+rows 决定）
    function gridContentHeight() {
        let maxY = 0
        let version = root.layoutVersion
        for (let i = 0; i < instanceIds.length; i++) {
            let y = Panel.widgetManager.instanceGridY(instanceIds[i])
            let rows = Panel.widgetManager.instanceRows(instanceIds[i])
            maxY = Math.max(maxY, y + rows)
        }
        return maxY * (cellHeight + cellSpacing) - cellSpacing
    }

    // ===== 拖放状态 =====
    property bool dragging: false
    property string dragInstanceId: ""
    property int dragCols: 1
    property int dragRows: 1
    property int dragTargetX: -1
    property int dragTargetY: -1
    property bool dragTargetValid: false
    // 上一次参与避让计算的格子：只有跨格时才重算布局，
    // 避免鼠标逐像素移动时反复重启多张卡片的位移动画造成卡顿。
    property int lastDragTargetX: -1
    property int lastDragTargetY: -1
    // 拖拽开始时的已提交布局快照：取消/失败时回弹用
    property var committedPositions: ({})
    // 长按时指针相对组件左上角的像素偏移：目标格 = 指针格 − 该偏移，
    // 保证宽/高较大的组件无论抓取哪个位置都能把左上角对准目标格
    property int dragGrabOffsetX: 0
    property int dragGrabOffsetY: 0

    // 把 C++ previewMove 返回的避让布局写入位置映射
    function applyPreviewLayout(layout) {
        if (!layout || layout.length === 0)
            return
        let positions = {}
        for (let i = 0; i < layout.length; i++) {
            let item = layout[i]
            positions[item.instanceId] = Qt.point(item.gridX, item.gridY)
        }
        root.gridPositions = positions
        root.layoutVersion++
    }

    // 长按组件开始拖拽：host 为网格实例容器，指针坐标已换算到 gridCanvas
    function startDrag(host, pointerX, pointerY) {
        if (root.dragging)
            return
        root.dragging = true
        root.dragInstanceId = host.modelData
        root.dragCols = Panel.widgetManager.instanceCols(host.modelData)
        root.dragRows = Panel.widgetManager.instanceRows(host.modelData)
        root.dragGrabOffsetX = pointerX - host.x
        root.dragGrabOffsetY = pointerY - host.y
        // 快照拖拽前的已提交布局，供取消/失败时动画回弹
        root.committedPositions = {}
        for (let key in root.gridPositions)
            root.committedPositions[key] = root.gridPositions[key]
        gridFlickable.interactive = false
        dragPreviewImage.source = ""
        dragPreview.visible = true
        // 抓取组件快照作为拖放预览（失败则仅显示占位框）
        host.grabToImage(function(result) {
            if (result && result.url.toString().length > 0)
                dragPreviewImage.source = result.url
        }, Qt.size(host.width, host.height))
        root.updateDrag(pointerX, pointerY)
    }

    // 按指针吸附到网格并更新预览
    function updateDrag(pointerX, pointerY) {
        if (!root.dragging)
            return
        // 目标格 = 组件左上角格：指针格扣除抓取偏移后钳制到网格可容纳范围。
        // 钳制保证宽 4 高 2 等大组件抓取任意位置都能自由放置（含最顶行）
        let targetX = Math.floor((pointerX - root.dragGrabOffsetX) / (cellWidth + cellSpacing))
        let targetY = Math.floor((pointerY - root.dragGrabOffsetY) / (cellHeight + cellSpacing))
        targetX = Math.max(0, Math.min(targetX, gridColumns - root.dragCols))
        targetY = Math.max(0, targetY)
        root.dragTargetX = targetX
        root.dragTargetY = targetY
        root.dragTargetValid = Panel.widgetManager.canDrop(root.dragInstanceId, targetX, targetY)
        let targetChanged = root.dragTargetX !== root.lastDragTargetX
            || root.dragTargetY !== root.lastDragTargetY
        root.lastDragTargetX = root.dragTargetX
        root.lastDragTargetY = root.dragTargetY
        // 预览跟随原始指针连续移动（仅做网格边界钳制），
        // 最终停放仍由 dragTargetX/Y 吸附格决定。
        let previewWidth = root.dragCols * cellWidth
            + (root.dragCols - 1) * cellSpacing
        let previewHeight = root.dragRows * cellHeight
            + (root.dragRows - 1) * cellSpacing
        dragPreview.x = Math.max(0,
            Math.min(pointerX - root.dragGrabOffsetX,
                     Math.max(0, gridCanvas.width - previewWidth)))
        dragPreview.y = Math.max(0,
            Math.min(pointerY - root.dragGrabOffsetY,
                     Math.max(0, gridCanvas.height - previewHeight)))
        if (root.dragTargetValid && targetChanged) {
            // 实时避让：目标格被占用时，被占组件立即动画让位（双向联动）
            let layout = Panel.widgetManager.previewMove(
                root.dragInstanceId, root.dragTargetX, root.dragTargetY)
            if (layout && layout.length > 0) {
                root.applyPreviewLayout(layout)
            } else {
                root.gridPositions = root.committedPositions
                root.layoutVersion++
            }
        } else if (!root.dragTargetValid && targetChanged) {
            // 越界：回弹到拖拽前布局
            root.gridPositions = root.committedPositions
            root.layoutVersion++
        }
    }

    // 结束拖拽：目标合法则提交 moveInstance；失败/取消则恢复拖拽前布局（动画回弹）
    function endDrag() {
        if (!root.dragging)
            return
        root.dragging = false
        gridFlickable.interactive = true
        dragPreview.visible = false
        dragPreviewImage.source = ""
        let committed = root.dragTargetValid
            && Panel.widgetManager.moveInstance(root.dragInstanceId, root.dragTargetX, root.dragTargetY)
        if (!committed) {
            root.gridPositions = root.committedPositions
            root.layoutVersion++
        }
        root.dragInstanceId = ""
        root.dragTargetX = -1
        root.dragTargetY = -1
        root.dragTargetValid = false
        root.lastDragTargetX = -1
        root.lastDragTargetY = -1
        root.dragGrabOffsetX = 0
        root.dragGrabOffsetY = 0
    }

    // 自动整理：压实布局并回到顶部（整理按钮与右键菜单共用）
    function autoArrangeNow() {
        Panel.widgetManager.autoArrangeAll()
        gridFlickable.contentY = 0
    }

    // 最近一次鼠标右键在主窗口坐标系中的 Y；-1 表示没有鼠标来源（如托盘 D-Bus）。
    property int lastPopupMouseY: -1

    // 设置类弹窗：以屏幕右缘为基准；主面板可见时向左避让，隐藏时贴屏幕右缘。
    function settingsPopupX(target) {
        if (!root.screen)
            return -target.width - 8
        if (Panel.visible)
            return -target.width - 8
        const screenRight = root.screen.virtualX + root.screen.width - 10
        return Math.round(screenRight - target.width - root.x)
    }

    // 打开前统一摆放弹窗：垂直中心对齐鼠标 Y（无鼠标时垂直居中），
    // 且上下边界始终落在主面板高度内。
    function positionPopup(target, mouseY) {
        const panelHeight = Math.max(1, root.height)
        const targetY = mouseY >= 0
            ? mouseY - target.height / 2
            : (panelHeight - target.height) / 2
        target.popupY = Math.max(0,
            Math.min(Math.round(targetY), Math.max(0, panelHeight - target.height)))

        if (target === settingsDialog || target === widgetSettingsDialog)
            target.popupX = root.settingsPopupX(target)
        else
            target.popupX = -target.width - 8
    }

    // 弹出面板互斥：添加/设置/关于同时只允许打开一个。
    // 打开目标前先关闭另外两个；目标已打开则关闭（切换语义）
    function openPanelPopup(target, mouseY) {
        if (target === addPopup) {
            settingsDialog.close()
            aboutDialog.close()
            widgetSettingsDialog.close()
        } else if (target === settingsDialog) {
            addPopup.close()
            aboutDialog.close()
            widgetSettingsDialog.close()
        } else if (target === aboutDialog) {
            addPopup.close()
            settingsDialog.close()
            widgetSettingsDialog.close()
        } else if (target === widgetSettingsDialog) {
            addPopup.close()
            settingsDialog.close()
            aboutDialog.close()
        }
        if (target.visible)
            target.close()
        else {
            root.positionPopup(target, mouseY === undefined ? -1 : mouseY)
            target.open()
        }
    }

    function openWidgetSettings(instanceId) {
        addPopup.close()
        settingsDialog.close()
        aboutDialog.close()
        root.positionPopup(widgetSettingsDialog, root.lastPopupMouseY)
        widgetSettingsDialog.openFor(instanceId)
    }

    function openWidgetMenu(instanceId, mouseY) {
        root.lastPopupMouseY = mouseY === undefined ? -1 : mouseY
        widgetContextMenu.rebuild(instanceId)
        widgetContextMenu.popup()
    }

    // ===== 窗口基础配置（与通知中心一致的尺寸与样式） =====

    // 与通知中心一致的尺寸：内容宽 360 + 左右各 10 padding
    property int contentPadding: 10
    property int contentWidth: 360

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
        if (visible) {
            applyLayerFlags()
            // 每次显示都重建 margin 绑定：dock 数据（DS.applet 返回值）不是
            // QML 可跟踪依赖，窗口重建后必须重新求值，否则边距保持旧值/0。
            // 同时启动轮询，兜底 dock 代理异步就绪晚于窗口创建的场景。
            refreshMargins()
            restartMarginRefresh()
        }
    }
    Component.onCompleted: {
        if (Qt.platform.pluginName === "xcb") {
            applyLayerFlags()
        }
        updateGridPositions()
        refreshMargins()
        restartMarginRefresh()
    }
    function applyLayerFlags() {
        // X11 下用 flags 直接表达层级：置顶 = WindowStaysOnTopHint（_NET_WM_STATE_ABOVE，
        // kwin 置顶），置底 = WindowStaysOnBottomHint（可被普通窗口覆盖）。
        // 不依赖 X11 LayerShellEmulation 的 layer→窗口类型映射：该映射只在 layerChanged
        // 信号时应用，窗口 hide/show 重建原生窗口后不会重新执行（QWindow 对象不变时
        // DLayerShellWindow 与模拟器都不会重建），导致窗口类型/层级丢失。
        // Wayland 下本函数不调用（合成器按 layer 管理），flags 无副作用。
        root.flags = layerIsBottom
            ? Qt.WindowStaysOnBottomHint | Qt.Tool | Qt.FramelessWindowHint
            : Qt.WindowStaysOnTopHint | Qt.Tool | Qt.FramelessWindowHint
    }

    // 四周统一边距：contentPadding + dock 边补偿（windowMargin）。
    // dock 边的补偿只覆盖 dock 自身高度，面板距 dock 的空隙 = contentPadding =
    // 距屏幕其他边缘的空隙，视觉对称。
    function desiredMargin(position) {
        return layerShellMargin(position) + contentPadding
    }

    // 直接赋值三条 margin：DS.applet() 的返回值不是 QML 可跟踪依赖，
    // 因此由轮询定时重算赋值（值不变时 setter 无操作，变化时触发 marginsChanged），
    // 避免 Qt.binding 重绑在 dock 数据迟到时失效导致边距保持旧值。
    function refreshMargins() {
        DLayerShellWindow.topMargin = desiredMargin(0)
        DLayerShellWindow.rightMargin = desiredMargin(1)
        DLayerShellWindow.bottomMargin = desiredMargin(2)
    }
    // 轮询刷新直到 dock 数据就绪且边距连续两次稳定，避免一次性延时错过
    // dock 插件晚于面板加载的窗口期（最多约 10s，之后静默保留当前边距）。
    property int marginRefreshTicks: 0
    function restartMarginRefresh() {
        marginRefreshTicks = 0
        marginRefreshTimer.restart()
    }
    Timer {
        id: marginRefreshTimer
        interval: 250
        repeat: true
        onTriggered: {
            marginRefreshTicks++
            if (marginRefreshTicks > 40) {
                stop()
                return
            }
            const beforeTop = DLayerShellWindow.topMargin
            const beforeRight = DLayerShellWindow.rightMargin
            const beforeBottom = DLayerShellWindow.bottomMargin
            refreshMargins()
            if (dockDataReady()
                && DLayerShellWindow.topMargin === beforeTop
                && DLayerShellWindow.rightMargin === beforeRight
                && DLayerShellWindow.bottomMargin === beforeBottom) {
                stop()
            }
        }
    }
    width: contentWidth + contentPadding * 2

    // 置顶：Overlay 层（在所有窗口之上）；置底：Buttom 层（可被普通窗口覆盖）
    DLayerShellWindow.layer: Panel.pinned
        ? DLayerShellWindow.LayerOverlay : DLayerShellWindow.LayerButtom
    // 注意：不再设置 exclusionZone。X11 下它会被 LayerShellEmulation 转成
    // _NET_WM_STRUT_PARTIAL 压缩整个工作区（导致全屏/最大化窗口被挤出黑边），
    // Wayland 下也会影响其他 layer-shell 窗口；而 dde-desktop 的桌面图标区域
    // 只按 dock 的 frontendWindowRect 计算、不读工作区，故 exclusionZone 对
    // 图标避让无效。置底时仅保留 LayerButtom 层语义，不再向合成器声明排除区域。
    DLayerShellWindow.anchors: DLayerShellWindow.AnchorRight
        | DLayerShellWindow.AnchorTop | DLayerShellWindow.AnchorBottom
    DLayerShellWindow.topMargin: desiredMargin(0)
    DLayerShellWindow.rightMargin: desiredMargin(1)
    DLayerShellWindow.bottomMargin: desiredMargin(2)
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

        // ===== 内容区：4 列网格 + 纵向滚动 =====
        Item {
            id: gridArea
            anchors {
                top: header.bottom
                topMargin: 8
                left: parent.left
                right: parent.right
                bottom: addButton.top
                bottomMargin: 8
            }

            // 空白处右键菜单：只接受右键，不影响组件左键长按拖拽
            MouseArea {
                id: blankContextArea
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                onClicked: function(mouse) {
                    var p = blankContextArea.mapToItem(root.contentItem, mouse.x, mouse.y)
                    root.lastPopupMouseY = p.y
                    contextMenu.popup()
                }
            }

            Flickable {
                id: gridFlickable
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: root.animatedGridContentHeight

                // DDE 样式滚动条：不活跃时自动隐藏（org.deepin.dtk ScrollBar）
                ScrollBar.vertical: ScrollBar {
                    anchors.right: parent.right
                }

                // 网格容器：按实例的 gridX/gridY/cols/rows 绝对定位
                Item {
                    id: gridCanvas
                    width: gridFlickable.width
                    height: gridFlickable.contentHeight

                    Repeater {
                        model: root.instanceIds
                        delegate: Item {
                            id: widgetHost
                            required property string modelData

                            x: root.cellX(modelData)
                            y: root.cellY(modelData)
                            width: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceCols(modelData) * cellWidth
                                    + (Panel.widgetManager.instanceCols(modelData) - 1) * cellSpacing
                            }
                            height: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceRows(modelData) * cellHeight
                                    + (Panel.widgetManager.instanceRows(modelData) - 1) * cellSpacing
                            }
                            // 拖拽中淡化原实例，预览快照随指针移动
                            opacity: root.dragging && modelData === root.dragInstanceId ? 0.35 : 1.0
                            // 位置变化动画：拖拽中其它实例实时让位、松手落位、整理、回弹都走这里
                            Behavior on x {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            // 尺寸切换动画：让组件在 1×1/2×2/4×2/4×4 之间平滑缩放
                            Behavior on width {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            Behavior on height {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            // 拖拽中淡化的原实例也平滑过渡
                            Behavior on opacity {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }

                            // 小组件渲染入口（qrc 或本地文件），由宿主按 widgetId 解析。
                            // 面板隐藏时卸载小组件对象树（释放 QML 对象与纹理内存），
                            // 显示时异步重建；各小组件 Component.onDestruction 已实现
                            // 采集/监控清理（setActive(false)/releaseMonitor 等）。
                            Loader {
                                id: widgetLoader
                                anchors.fill: parent
                                active: Panel.visible
                                asynchronous: true
                                source: Panel.widgetManager.entryUrl(Panel.widgetManager.instanceWidgetId(modelData))
                            }

                            // 拖放层：普通点击透传给组件内容，长按进入拖拽
                            MouseArea {
                                id: widgetDragArea
                                anchors.fill: parent
                                z: widgetLoader.z + 1
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                pressAndHoldInterval: 500
                                // 普通点击转交组件内容处理（如便签取焦），拖拽由 pressAndHold 接管。
                                // 按下必须被本层接受以持有鼠标抓取，否则避让时卡片移开后松开事件会丢失。
                                property bool suppressClick: false

                                onPressed: function(mouse) {
                                    suppressClick = false
                                    var pressedWidget = widgetLoader.item
                                    if (pressedWidget
                                        && typeof pressedWidget.handleHostPressed === "function")
                                        pressedWidget.handleHostPressed(mouse.x, mouse.y)
                                }
                                onPressAndHold: function(mouse) {
                                    suppressClick = true
                                    var p = widgetDragArea.mapToItem(gridCanvas, mouse.x, mouse.y)
                                    root.startDrag(widgetHost, p.x, p.y)
                                }
                                onPositionChanged: function(mouse) {
                                    if (root.dragging) {
                                        var p = widgetDragArea.mapToItem(gridCanvas, mouse.x, mouse.y)
                                        root.updateDrag(p.x, p.y)
                                        return
                                    }
                                    var hoverWidget = widgetLoader.item
                                    if (hoverWidget
                                        && typeof hoverWidget.handleHostHover === "function")
                                        hoverWidget.handleHostHover(mouse.x, mouse.y)
                                }
                                onReleased: function(mouse) {
                                    var releasedWidget = widgetLoader.item
                                    if (releasedWidget
                                        && typeof releasedWidget.handleHostReleased === "function")
                                        releasedWidget.handleHostReleased(mouse.x, mouse.y)
                                    if (root.dragging)
                                        root.endDrag()
                                    else
                                        suppressClick = false
                                }
                                onCanceled: function(mouse) {
                                    var canceledWidget = widgetLoader.item
                                    if (canceledWidget
                                        && typeof canceledWidget.handleHostReleased === "function")
                                        canceledWidget.handleHostReleased(mouse.x, mouse.y)
                                    suppressClick = false
                                    if (root.dragging)
                                        root.endDrag()
                                }
                                onExited: function() {
                                    var hoverWidget = widgetLoader.item
                                    if (hoverWidget
                                        && typeof hoverWidget.handleHostHover === "function")
                                        hoverWidget.handleHostHover(-1, -1)
                                }
                                onClicked: function(mouse) {
                                    if (suppressClick) {
                                        suppressClick = false
                                        return
                                    }
                                    if (root.dragging)
                                        return
                                    // 把普通点击转交给组件内容（如便签 TextArea 取焦），
                                    // 避免按下已被拖放层接收后组件无法编辑。
                                    var widget = widgetLoader.item
                                    if (widget && typeof widget.handleHostClick === "function")
                                        widget.handleHostClick(mouse.x, mouse.y)
                                }
                            }

                            // 右键菜单层：只接收右键，不影响左键点击与长按拖拽
                            MouseArea {
                                id: widgetContextArea
                                anchors.fill: parent
                                z: widgetDragArea.z + 1
                                acceptedButtons: Qt.RightButton
                                onClicked: function(mouse) {
                                    var p = widgetContextArea.mapToItem(
                                        root.contentItem, mouse.x, mouse.y)
                                    root.openWidgetMenu(widgetHost.modelData, p.y)
                                }
                            }

                            // 实例配置对象：初始加载时注入，保存后由 Connections 刷新
                            property var widgetConfig: Panel.widgetManager.instanceConfig(widgetHost.modelData)
                            property int hostCols: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceCols(widgetHost.modelData)
                            }
                            property int hostRows: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceRows(widgetHost.modelData)
                            }

                            Connections {
                                target: Panel.widgetManager
                                function onInstanceConfigChanged(instanceId) {
                                    if (instanceId === widgetHost.modelData) {
                                        widgetHost.widgetConfig =
                                            Panel.widgetManager.instanceConfig(instanceId)
                                    }
                                }
                            }

                            // 注入实例上下文（开放接口的一部分）：
                            // dataDir 为宿主隔离的实例数据目录，instanceId 标识实例。
                            // 用 Binding 注入：小组件根对象创建后即生效并持续同步
                            //（onLoaded 注入晚于小组件 Component.onCompleted，会导致初始读取失效）。
                            Binding {
                                target: widgetLoader.item
                                property: "dataDir"
                                value: widgetHost.dataDir
                            }
                            Binding {
                                target: widgetLoader.item
                                property: "instanceId"
                                value: widgetHost.modelData
                            }
                            Binding {
                                target: widgetLoader.item
                                property: "widgetConfig"
                                value: widgetHost.widgetConfig
                            }
                            Binding {
                                target: widgetLoader.item
                                property: "hostCols"
                                value: widgetHost.hostCols
                            }
                            Binding {
                                target: widgetLoader.item
                                property: "hostRows"
                                value: widgetHost.hostRows
                            }

                            // 小组件实例数据目录（示例：todo 便签持久化）
                            property string dataDir: Panel.widgetManager.widgetDataDir(
                                Panel.widgetManager.instanceWidgetId(modelData))
                        }
                    }

                    // 拖放预览：跟随指针的组件快照 + 有效/无效边框
                    Item {
                        id: dragPreview
                        visible: false
                        z: 10
                        width: root.dragCols * cellWidth + (root.dragCols - 1) * cellSpacing
                        height: root.dragRows * cellHeight + (root.dragRows - 1) * cellSpacing
                        // 拖拽预览平滑跟随指针，避免逐格硬跳
                        Behavior on x {
                            SmoothedAnimation {
                                velocity: 1000
                                reversingMode: SmoothedAnimation.Immediate
                            }
                        }
                        Behavior on y {
                            SmoothedAnimation {
                                velocity: 1000
                                reversingMode: SmoothedAnimation.Immediate
                            }
                        }

                        Image {
                            id: dragPreviewImage
                            anchors.fill: parent
                            anchors.margins: 3
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: DTK.platformTheme.windowRadius
                            color: Qt.rgba(0.35, 0.6, 1.0, 0.12)
                            border.width: 2
                            border.color: root.dragTargetValid
                                ? Qt.rgba(0.35, 0.78, 0.42, 1)
                                : Qt.rgba(0.95, 0.35, 0.35, 1)
                        }
                    }

                    // 空态占位
                    Text {
                        anchors.centerIn: parent
                        visible: root.instanceIds.length === 0
                        text: qsTr("No widgets yet")
                        font: DTK.fontManager.t5
                        color: palette.windowText
                        opacity: 0.6
                    }
                }
            }
        }

        // ===== 底部左下角"整理"按钮 =====
        Button {
            id: arrangeButton
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            width: 88
            height: 32
            text: qsTr("Arrange")
            onClicked: autoArrangeNow()
        }

        // ===== 底部右下角"添加"按钮 =====
        Button {
            id: addButton
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            width: 88
            height: 32
            icon.name: "add"
            text: qsTr("Add")
            onClicked: addPopup.open()
        }
    }

    // ===== 右键菜单（面板空白处） =====
    Menu {
        id: contextMenu

        MenuItem {
            text: qsTr("Add widget")
            onTriggered: openPanelPopup(addPopup, root.lastPopupMouseY)
        }
        MenuItem {
            text: qsTr("Arrange")
            onTriggered: autoArrangeNow()
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Settings")
            onTriggered: openPanelPopup(settingsDialog, root.lastPopupMouseY)
        }
        MenuItem {
            text: qsTr("About")
            onTriggered: openPanelPopup(aboutDialog, root.lastPopupMouseY)
        }
    }

    // ===== 小组件右键菜单项组件（按当前实例可见项动态重建） =====
    Component {
        id: sizeMenuEntry

        MenuItem {
            property string instanceId: ""
            property int cols: 1
            property int rows: 1

            onTriggered: Panel.widgetManager.setInstanceSize(instanceId, cols, rows)
        }
    }

    Component {
        id: settingsMenuEntry

        MenuItem {
            property string instanceId: ""

            onTriggered: root.openWidgetSettings(instanceId)
        }
    }

    Component {
        id: removeMenuEntry

        MenuItem {
            property string instanceId: ""

            onTriggered: Panel.widgetManager.removeInstance(instanceId)
        }
    }

    Component {
        id: menuSeparatorEntry

        MenuSeparator { }
    }

    // ===== 单个小组件的右键菜单（每次打开按可见项重建，高度随内容收缩） =====
    Menu {
        id: widgetContextMenu

        property string currentInstanceId: ""
        property string currentWidgetId: ""
        property var builtItems: []

        function addEntry(component, props) {
            var item = component.createObject(view, props)
            widgetContextMenu.addItem(item)
            widgetContextMenu.builtItems.push(item)
            return item
        }

        function rebuild(instanceId) {
            widgetContextMenu.currentInstanceId = instanceId
            widgetContextMenu.currentWidgetId =
                Panel.widgetManager.instanceWidgetId(instanceId)

            // 先移除上一次打开的菜单项，避免隐藏项继续占位撑高菜单
            for (var i = widgetContextMenu.builtItems.length - 1; i >= 0; --i) {
                var oldItem = widgetContextMenu.builtItems[i]
                widgetContextMenu.removeItem(oldItem)
                oldItem.destroy()
            }
            widgetContextMenu.builtItems = []

            var sizeOptions = [
                { "cols": 1, "rows": 1, "label": qsTr("Small") + " 1×1" },
                { "cols": 2, "rows": 2, "label": qsTr("Medium") + " 2×2" },
                { "cols": 4, "rows": 2, "label": qsTr("Wide") + " 4×2" },
                { "cols": 4, "rows": 4, "label": qsTr("Large") + " 4×4" }
            ]
            var hasSize = false
            for (var s = 0; s < sizeOptions.length; ++s) {
                var option = sizeOptions[s]
                if (!Panel.widgetManager.isSizeSupported(
                        widgetContextMenu.currentWidgetId, option.cols, option.rows)) {
                    continue
                }
                widgetContextMenu.addEntry(sizeMenuEntry, {
                    "instanceId": instanceId,
                    "cols": option.cols,
                    "rows": option.rows,
                    "text": option.label
                })
                hasSize = true
            }

            if (hasSize)
                widgetContextMenu.addEntry(menuSeparatorEntry, {})

            if (Panel.widgetManager.widgetSettingsSchema(
                    widgetContextMenu.currentWidgetId).length > 0) {
                widgetContextMenu.addEntry(settingsMenuEntry, {
                    "instanceId": instanceId,
                    "text": qsTr("Settings…")
                })
            }

            widgetContextMenu.addEntry(removeMenuEntry, {
                "instanceId": instanceId,
                "text": qsTr("Remove")
            })
        }
    }

    // ===== 设置与关于对话框 =====
    SettingsDialog {
        id: settingsDialog
    }
    AboutPopup {
        id: aboutDialog
    }

    WidgetSettingsPopup {
        id: widgetSettingsDialog
    }

    // 托盘右键菜单经 D-Bus 触发的动作统一在这里执行
    Connections {
        target: Panel
        function onSettingsRequested() {
            openPanelPopup(settingsDialog)
        }
        function onAboutRequested() {
            openPanelPopup(aboutDialog)
        }
        function onAddWidgetRequested() {
            openPanelPopup(addPopup)
        }
        function onAutoArrangeRequested() {
            autoArrangeNow()
        }
    }

    // ===== 添加小组件弹出面板 =====
    AddWidgetPopup {
        id: addPopup
    }
}
