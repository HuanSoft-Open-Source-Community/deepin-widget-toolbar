// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// 单个小组件实例的宿主容器（主面板网格 Repeater 的委托）：
// 由主面板传入网格几何与拖拽状态；内部负责小组件 Loader、
// 拖放层（普通点击透传给组件内容、长按进入拖拽）、右键菜单层、
// 卡片下方的名称条（全局开关；名称开销取自高度：格高变高 + 卡片最多让 4px，
// 卡片宽度始终保持满列宽，故各卡宽度视觉一致），
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
    // 格高：关闭名称时等于格宽（正方形），启用名称时略高于格宽。槽高按它计算，
    // 故行距/坐标/滚动范围（主面板侧）与这里始终同源，不会出现卡片与槽位错位。
    property real cellHeight: 0
    property real cellSpacing: 0
    // 纵向格距：与网格行距里的空隙同源（主面板在显示名称时取 cardLabelGap，
    // 使文字上下间距相等）。默认跟横向格距，独立复用时行为与旧版一致。
    property real cellSpacingY: root.cellSpacing
    // 卡片下方名称条高度，由主面板按全局开关给出；0 = 不显示名称，
    // 此时卡片恰好铺满槽位，几何与未提供本功能时逐像素一致。
    property real cardLabelHeight: 0
    // 名称盒与本卡片之间的间隙；主面板在显示名称时把纵向格距也设为它，
    // 于是名称盒上下两侧的间隙相同、盒内文字垂直居中 ⇒ 文字上下间距相同。
    property real cardLabelGap: 2

    // 本实例槽位尺寸（= 本 Item 的 width/height，网格坐标系不变）
    readonly property real slotWidth: root.cols * root.cellWidth + (root.cols - 1) * root.cellSpacing
    readonly property real slotHeight: root.rows * root.cellHeight + (root.rows - 1) * root.cellSpacingY
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
    // 宿主容器始终占满槽位：卡片在其中缩小，名称条落在卡片下方的槽内余量里。
    // 尺寸/位置变化由下面的 Behavior 缓动，本 Item 的 width/height 即动画中的
    // 实时几何；卡片渲染盒（cardBox）绑定这两个动画属性，卡片本体与内部内容
    // 才随缓动逐帧重排。root 裁剪作为防溢出保险：任何内部绘制不得越出动画框。
    width: root.slotWidth
    height: root.slotHeight
    clip: true
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

    // 卡片实际渲染框：满列宽、顶对齐，槽底那条留给名称。
    // 宽度在任何开关状态下都等于槽宽（不缩放）——各卡片左右边缘始终与列对齐，
    // 名称的开销只从高度上取：格高增量承担大部分，卡片自己只让出 4px。
    // 只做定位盒，不裁剪；小组件按这里的真实像素重排布局。
    // 绑定宿主的**动画几何**（root.width/height，Behavior 每帧驱动其变化），
    // 于是尺寸切换时卡片背景与内部内容整段缓动缩放，而非单帧跳终值；
    // 名称条高度在动画全程恒为 cardLabelHeight，落点随卡片下缘平滑移动。
    Item {
        id: cardBox
        x: 0
        y: 0
        width: root.width
        height: Math.max(0, root.height - root.cardLabelHeight)
    }

    // 小组件渲染入口（qrc 或本地文件），由宿主按 widgetId 解析。
    // 面板隐藏时卸载小组件对象树（释放 QML 对象与纹理内存），
    // 显示时异步重建；各小组件 Component.onDestruction 已实现
    // 采集/监控清理（setActive(false)/releaseMonitor 等）。
    Loader {
        id: widgetLoader
        anchors.fill: cardBox
        active: Panel.visible
        asynchronous: true
        source: Panel.widgetManager.entryUrl(Panel.widgetManager.instanceWidgetId(root.instanceId))
    }

    // 卡片下方名称：全局开关控制（无单卡片粒度），宽度锚定卡片——也就是整列宽，
    // 故"不超过卡片宽度 + 溢出省略号"由几何天然成立，且可用宽度最大化（省略更少）。
    // 只依赖 widgetId，小组件对象树卸载期间照常显示；随宿主 opacity 一并淡化。
    Text {
        id: cardNameLabel
        anchors.horizontalCenter: cardBox.horizontalCenter
        anchors.top: cardBox.bottom
        anchors.topMargin: root.cardLabelGap
        width: cardBox.width
        // 盒底恰好落在槽底：名称条高 cardLabelHeight 中，上侧让出 cardLabelGap，
        // 其余归文字盒；盒下沿到下一行卡片的距离由纵向格距给出，主面板在显示
        // 名称时设成同一个 cardLabelGap，故上下对称、文字垂直居中于两张卡片之间。
        height: Math.max(0, root.cardLabelHeight - root.cardLabelGap)
        visible: root.cardLabelHeight > 0
        text: Panel.widgetManager.displayName(
            Panel.widgetManager.instanceWidgetId(root.instanceId))
        font: DTK.fontManager.t7
        color: palette.windowText
        opacity: 0.75
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    // 拖放层：普通点击透传给组件内容，长按进入拖拽。
    // 与 Loader 同样锚定 cardBox：本层局部坐标即小组件坐标，
    // 卡片缩小后 handleHost* 转交的坐标才不会偏移。
    MouseArea {
        id: widgetDragArea
        anchors.fill: cardBox
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

    // 右键菜单层：只接收右键，不影响左键点击与长按拖拽。
    // 刻意保持铺满**整个槽位**（而非 cardBox）：卡片缩小后名称条落在槽内余量里，
    // 右键名称也要弹出该组件的菜单，而不是落到面板空白区弹出面板菜单。
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
