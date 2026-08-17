// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.ds 1.0

// 单个小组件实例的宿主容器（主面板网格 Repeater 的委托）：
// 由主面板传入网格几何与拖拽状态；内部负责小组件 Loader、
// 拖放层（普通点击透传给组件内容、长按进入拖拽）、右键菜单层，
// 以及实例上下文注入（dataDir/instanceId/widgetConfig/hostCols/hostRows/
// hostCardTransparent）。拖拽与右键事件以 dragSurface/menuSurface
// 空间的坐标发出，由主面板的拖拽状态机/菜单逻辑处理。
Item {
    id: root

    // ===== 宿主注入 =====
    property string instanceId: ""
    property real gridX: 0
    property real gridY: 0
    property int cols: 2
    property int rows: 2
    property real cellWidth: 0
    property real cellSpacing: 0
    // 拖拽中淡化原实例，预览快照随指针移动
    property bool dimmed: false
    // 面板拖拽状态机是否进行中（由主面板同步）
    property bool panelDragging: false
    // 坐标映射目标：拖拽 → 网格画布；右键菜单 → 窗口内容区
    property var dragSurface: null
    property var menuSurface: null

    // ===== 事件信号（坐标为 dragSurface/menuSurface 空间） =====
    signal dragStartRequested(var host, real x, real y)
    signal dragMoveRequested(var host, real x, real y)
    signal dragEndRequested(var host)
    signal contextMenuRequested(real x, real y)

    x: root.gridX
    y: root.gridY
    width: root.cols * root.cellWidth + (root.cols - 1) * root.cellSpacing
    height: root.rows * root.cellWidth + (root.rows - 1) * root.cellSpacing
    opacity: root.dimmed ? 0.35 : 1.0
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
        source: Panel.widgetManager.entryUrl(Panel.widgetManager.instanceWidgetId(root.instanceId))
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
            var p = widgetDragArea.mapToItem(root.dragSurface, mouse.x, mouse.y)
            root.dragStartRequested(root, p.x, p.y)
        }
        onPositionChanged: function(mouse) {
            if (root.panelDragging) {
                var p = widgetDragArea.mapToItem(root.dragSurface, mouse.x, mouse.y)
                root.dragMoveRequested(root, p.x, p.y)
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
            if (root.panelDragging)
                root.dragEndRequested(root)
            else
                suppressClick = false
        }
        onCanceled: function(mouse) {
            var canceledWidget = widgetLoader.item
            if (canceledWidget
                && typeof canceledWidget.handleHostReleased === "function")
                canceledWidget.handleHostReleased(mouse.x, mouse.y)
            suppressClick = false
            if (root.panelDragging)
                root.dragEndRequested(root)
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
            if (root.panelDragging)
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
            var p = widgetContextArea.mapToItem(root.menuSurface, mouse.x, mouse.y)
            root.contextMenuRequested(p.x, p.y)
        }
    }

    // 实例配置对象：初始加载时注入，保存后由 Connections 刷新
    property var widgetConfig: Panel.widgetManager.instanceConfig(root.instanceId)
    property int hostCols: {
        let version = root.cols
        return Panel.widgetManager.instanceCols(root.instanceId)
    }
    property int hostRows: {
        let version = root.rows
        return Panel.widgetManager.instanceRows(root.instanceId)
    }

    Connections {
        target: Panel.widgetManager
        function onInstanceConfigChanged(instanceId) {
            if (instanceId === root.instanceId) {
                root.widgetConfig = Panel.widgetManager.instanceConfig(instanceId)
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
        value: root.dataDir
    }
    Binding {
        target: widgetLoader.item
        property: "instanceId"
        value: root.instanceId
    }
    Binding {
        target: widgetLoader.item
        property: "widgetConfig"
        value: root.widgetConfig
    }
    Binding {
        target: widgetLoader.item
        property: "hostCols"
        value: root.hostCols
    }
    Binding {
        target: widgetLoader.item
        property: "hostRows"
        value: root.hostRows
    }
    // 面板级"卡片透明模式"：与实例自身透明开关解耦，
    // 只作用于 WidgetCard 背景层
    Binding {
        target: widgetLoader.item
        property: "hostCardTransparent"
        value: Panel.cardTransparent
    }

    // 小组件实例数据目录（示例：todo 便签持久化）
    property string dataDir: Panel.widgetManager.widgetDataDir(
        Panel.widgetManager.instanceWidgetId(root.instanceId))
}
