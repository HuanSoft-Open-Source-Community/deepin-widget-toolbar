// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.dtk.style 1.0 as DStyle
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "widgets/components" as Components

Window {
    id: root

    // 获取 dock 所在的屏幕，侧栏跟随该屏幕显示。
    // 对象取自 DockMarginHelper 缓存的 dockApplet，而非现场调 DS.applet()：
    // 后者是函数调用、返回值不可被 QML 跟踪，读缓存对象的 screenName 属性才会让
    // 本绑定在 dock 换屏时自动重算（缓存未就绪时回退首屏，与旧行为一致）。
    function getDockScreen() {
        let dockApplet = dockMargin.dockApplet
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

    // 与任务栏之间的间距计算已迁移到 components/DockMarginHelper.qml
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
    // 占用区顶行（最上卡片的最顶行）：滚动内容与卡片渲染的归一化基准。
    // 最上卡片上方的空洞格不计入滚动高度（新增实例会自动填充首个空闲
    // 矩形，空洞本就不可见）；空网格为 0。
    property int liveGridTopRow: {
        let minY = Infinity
        for (let id in gridPositions)
            minY = Math.min(minY, gridPositions[id].y)
        return minY === Infinity ? 0 : minY
    }
    // 拖拽期间冻结的顶行（gridTopRow 的取值来源）：虚影（被拖实例）在拖拽中也留在
    // gridPositions 里并随目标格移动，若归一化基准跟着它走，拖着最上卡片下移会在
    // 拖拽中途改变基准——整块网格重排，同时位移视口补偿与"指针→网格"换算
    // （目标格会跳格）。冻结只压住"顶行抬升"：虚影下移、原位让出空洞都不许抬升
    // 基准；但避让把某张卡临时挪到基准之上时仍跟随下降（取两者较小），否则那张卡
    // 会渲染在画布上边界之外、拖拽全程不可见。startDrag 捕获、endDrag 末尾释放；
    // 释放时布局已定型，故只在落位处产生一次顶行变化（与改动前同一时机）。
    property bool topRowFrozen: false
    property int frozenGridTopRow: 0
    property int gridTopRow: root.topRowFrozen
        ? Math.min(root.frozenGridTopRow, root.liveGridTopRow)
        : root.liveGridTopRow
    property int lastGridTopRow: 0
    onGridTopRowChanged: {
        // 顶行变化（删除最上卡片/避让预览移动顶卡）时同步平移视口，保持卡片视觉
        // 位置稳定：卡片画布坐标 = (gy - gridTopRow) * pitch，顶行每增大 1 行，
        // 同一张卡在画布上就上移一个 pitch；要让它在屏幕上不动，视口在内容坐标里
        // 必须同样上移一个 pitch，即 contentY 减去同一个增量（方向与 cellY 相反）。
        // 钳制用 animatedGridContentHeight（真正驱动 contentHeight/canvas 高度的
        // 动画值），而非即时的 gridContentHeight，否则动画期间两者不等、钳制会失真。
        // 程序化写入的 contentY 不会被 Flickable 自动钳制（Qt 6.8 实测越界值会残留），
        // 故必须显式钳到 [0, maxContentY]。
        gridFlickable.contentY -= (gridTopRow - lastGridTopRow)
            * (cellHeight + cellSpacingY)
        let maxContentY = Math.max(animatedGridContentHeight, gridFlickable.height)
            - gridFlickable.height
        gridFlickable.contentY = Math.max(0,
            Math.min(gridFlickable.contentY, maxContentY))
        lastGridTopRow = gridTopRow
    }
    // 网格内容高度的动画代理：尺寸切换时滚动范围平滑过渡。钳制到网格
    // 可视区高度（而非整窗高度）：内容不足一屏时完全不可滚动。
    property int animatedGridContentHeight: Math.max(gridContentHeight(),
                                                     gridFlickable.height)
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

    // 实例左上角像素坐标；位置映射未就绪时回退到 C++ 直接读取。
    // Y 以占用区顶行为基准归一化（整块占用区贴住画布顶部）
    function cellX(instanceId) {
        let p = root.gridPositions[instanceId]
        return (p ? p.x : Panel.widgetManager.instanceGridX(instanceId)) * (cellWidth + cellSpacing)
    }
    function cellY(instanceId) {
        let p = root.gridPositions[instanceId]
        let gy = p ? p.y : Panel.widgetManager.instanceGridY(instanceId)
        return (gy - root.gridTopRow) * (cellHeight + cellSpacingY)
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

    // 网格参数：横向固定 4 列，纵向行数不限（滚动范围按卡片占用区动态计算）
    property int gridColumns: 4
    // 卡片间距：8 → 12，不再紧凑但也不显空旷
    property int cellSpacing: 12
    // 名称条与卡片之间的间隙（上侧）：纵向格距在显示名称时取同一数值，于是
    // "文字到上方卡片"与"文字到下方卡片"的距离严格相等——名称盒上缘距本卡
    // cardLabelGap、下缘距下一行卡片也是 cardLabelGap，文字在盒内垂直居中，
    // 两侧余量相同，故与字号无关地保持对称（不需要测量文字高度）。
    readonly property int cardLabelGap: 2
    // 纵向格距（行距里的空隙）：横向恒用 cellSpacing（列宽与横向对齐不变）；
    // 纵向在**显示名称时**取 cardLabelGap，即把"文字下间距"砍到与上间距相同。
    // 关闭名称时等于 cellSpacing，几何与没有本功能时逐像素一致。
    // 注：纵向格距同时也是多行卡片内部的格距，故多行卡片会随 rows−1 相应变矮
    //（2 行 −6px、4 行 −18px，相对未启用名称时），这是统一行距下的必然结果。
    readonly property int cellSpacingY: Panel.showCardNames ? cardLabelGap : cellSpacing
    property int cellWidth: Math.floor((gridArea.width - (gridColumns - 1) * cellSpacing) / gridColumns)
    // 卡片下方名称条的高度（按主题 t7 字号推导，字体放大时同步增高，不会挤压）；
    // 关闭名称时为 0，格高与卡片几何逐像素等于没有本功能时。
    readonly property int cardLabelHeight: Panel.showCardNames
        ? Math.round(DTK.fontManager.t7.pixelSize + 9) : 0
    // 名称条里由卡片让出的高度上限：其余增量由格高承担（"卡片最多缩小 4 像素"）。
    // 只影响高度，**卡片宽度任何时候都不缩**，故各卡宽度与关闭时完全一致。
    readonly property int cardLabelShrink: 4
    // 关闭名称：格子为正方形，2×2 小组件占 (2*cellWidth + spacing) 见方（旧行为）。
    // 启用名称：格子变为略高的长方形（高 = 宽 + 名称条高 − 4），名称占用格底一条，
    // 卡片因此保持满列宽——宽度视觉谐调、横向对齐不破；名称条每卡只有一条而格高
    // 每行都增，多行卡片随格高相应变高（1×1/4×1 只矮 4px）。
    // 行距/坐标/滚动范围都读 cellHeight，故格高一变即自动跟随，无需改动那些公式。
    property int cellHeight: cellWidth + (Panel.showCardNames
        ? cardLabelHeight - cardLabelShrink : 0)

    // 网格内容总高度：占用区跨度 = 渲染基准顶行 → 最下卡片底行（含），
    // 上/下方的空白格不再计入滚动范围。拖拽中末尾多留一行，保证能把
    // 卡片拖到当前最底行之下落位（canDrop 对行数无上限）。空网格为 0
    // （由 animatedGridContentHeight 钳到可视区高度）。
    function gridContentHeight() {
        let ids = root.instanceIds
        if (ids.length === 0)
            return 0
        let version = root.layoutVersion
        let minY = Infinity
        let maxY = 0
        for (let i = 0; i < ids.length; i++) {
            let p = root.gridPositions[ids[i]]
            let y = p ? p.y : Panel.widgetManager.instanceGridY(ids[i])
            let rows = Panel.widgetManager.instanceRows(ids[i])
            minY = Math.min(minY, y)
            maxY = Math.max(maxY, y + rows)
        }
        // 画布从渲染基准（gridTopRow）起算，而不是从"当前最上卡片"起算：拖拽中
        // 虚影离开顶行后两者会差出一段空洞，按最上卡片算会让渲染位置落到内容
        // 高度之外（底部被裁、预览钳制失真）。非拖拽时两者恒等，行为不变。
        minY = Math.min(minY, root.gridTopRow)
        let bottomRow = maxY + (root.dragging ? 1 : 0)
        return (bottomRow - minY) * (cellHeight + cellSpacingY) - cellSpacingY
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
        // 虚影落点：previewMove 的 computeAvoidance 把拖拽源固定在原位（fixedId），
        // 这里把它覆写为吸附后的目标格——原位的半透明虚影跟着目标格逐格移动，
        // 松手前即可看到"会落在哪"。覆写值与 moveInstance 提交后的坐标逐格一致
        // （两侧都基于同一次 computeAvoidance + 目标格），故落位无二次位移；
        // 目标无效时 updateDrag 整体回退到 committedPositions，虚影随之弹回原位。
        if (root.dragging && root.dragTargetValid)
            positions[root.dragInstanceId] = Qt.point(root.dragTargetX, root.dragTargetY)
        root.gridPositions = positions
        root.layoutVersion++
    }

    // 长按组件开始拖拽：host 为网格实例容器，指针坐标已换算到 gridCanvas
    function startDrag(host, pointerX, pointerY) {
        if (root.dragging)
            return
        // 顶行基准在拖拽全程冻结（此时 gridPositions 仍是已提交布局）
        root.frozenGridTopRow = root.gridTopRow
        root.topRowFrozen = true
        root.dragging = true
        root.dragInstanceId = host.instanceId
        root.dragCols = Panel.widgetManager.instanceCols(host.instanceId)
        root.dragRows = Panel.widgetManager.instanceRows(host.instanceId)
        root.dragGrabOffsetX = pointerX - host.x
        root.dragGrabOffsetY = pointerY - host.y
        // 快照拖拽前的已提交布局，供取消/失败时动画回弹
        root.committedPositions = {}
        for (let key in root.gridPositions)
            root.committedPositions[key] = root.gridPositions[key]
        gridFlickable.interactive = false
        dragPreviewImage.source = ""
        // 先按指针瞬移到位、再显示、再恢复平滑跟随：Behavior 若在本次拖拽的
        // 首个位置赋值时生效，预览会从上一次拖拽的停留点（面板首次拖拽为 0,0）
        // 补间飞向指针，方向随历史变化——即"莫名从四个方向飞入"。
        dragPreview.snapToPointer = true
        root.updateDrag(pointerX, pointerY)
        dragPreview.visible = true
        dragPreview.snapToPointer = false
        // 抓取组件快照作为拖放预览（失败则仅显示占位框）
        host.grabToImage(function(result) {
            if (result && result.url.toString().length > 0)
                dragPreviewImage.source = result.url
        }, Qt.size(host.width, host.height))
    }

    // 按指针吸附到网格并更新预览
    function updateDrag(pointerX, pointerY) {
        if (!root.dragging)
            return
        // 目标格 = 组件左上角格：指针格扣除抓取偏移后钳制到网格可容纳范围。
        // 钳制保证宽 4 高 2 等大组件抓取任意位置都能自由放置（含最顶行）。
        // 指针坐标是画布空间：画布行 + 占用区顶行 = 网格行（画布顶部即
        // 最上卡片顶行，见 gridTopRow）。
        let targetX = Math.floor((pointerX - root.dragGrabOffsetX) / (cellWidth + cellSpacing))
        let targetY = Math.max(0, Math.floor((pointerY - root.dragGrabOffsetY)
            / (cellHeight + cellSpacingY))) + root.gridTopRow
        targetX = Math.max(0, Math.min(targetX, gridColumns - root.dragCols))
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
            + (root.dragRows - 1) * cellSpacingY
        dragPreview.x = Math.max(0,
            Math.min(pointerX - root.dragGrabOffsetX,
                     Math.max(0, gridCanvas.width - previewWidth)))
        // 纵向可达范围用「目标内容高度」而非 gridCanvas.height：后者绑的是
        // 220ms 动画中的 animatedGridContentHeight，虚影下移时上限会滞后一个动画周期。
        dragPreview.y = Math.max(0,
            Math.min(pointerY - root.dragGrabOffsetY,
                     Math.max(0, Math.max(root.gridContentHeight(), gridFlickable.height)
                              - previewHeight)))
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
        dragPreview.snapToPointer = false
        // 顶行冻结最后释放：此刻 gridPositions 已是提交或回滚后的最终布局
        // （moveInstance 的 layoutChanged 同步写回），只产生一次顶行变化，
        // 与改动前的落位时机一致；取消/回滚时冻结值就是已提交布局的顶行，
        // 释放不触发视口补偿。
        root.topRowFrozen = false
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

    // 收起本面板全部二级弹窗与菜单：任一避让（MMV / 外部面板）开始时调用。
    // 四类 PanelPopup 挂在独立的辅助顶层窗口（Panel.popupWindow）上，不随主
    // 窗口隐藏，留着会被 MMV 当普通窗口收录成缩略图、或与外部面板叠合；
    // 窗口内 Menu 一并 close 防止恢复后残开。
    function closeAllPopups() {
        addPopup.close()
        settingsDialog.close()
        aboutDialog.close()
        widgetSettingsDialog.close()
        appPickerDialog.close()
        contextMenu.close()
        widgetContextMenu.close()
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

    // C++ QVariantList 可能以"类数组对象"到达 QML（Array.isArray 不成立），
    // 回写前统一容错提取（与 applauncher/SettingsRow 同一规则）
    function asAppList(value) {
        if (value === undefined || value === null)
            return []
        if (Array.isArray(value))
            return value
        if (typeof value === "object") {
            var out = []
            if (typeof value.length === "number") {
                for (var i = 0; i < value.length; ++i)
                    out.push(value[i])
                return out
            }
            for (var k in value)
                out.push(value[k])
            return out
        }
        return []
    }

    // 打开"选择程序"三级面板（卡片内"+"或启动器行触发，index=-1 表示追加）
    function openAppPickerFor(instanceId, index) {
        addPopup.close()
        settingsDialog.close()
        aboutDialog.close()
        widgetSettingsDialog.close()

        var cfg = Panel.widgetManager.instanceConfig(instanceId)
        var list = root.asAppList(cfg ? cfg.launchers : undefined)
        var current = (index >= 0 && index < list.length) ? [String(list[index])] : []
        var maxSelect = 1
        if (index < 0) {
            // 追加空位（卡片内"+"）：多选上限 = 剩余空位（容量 - 已配置，≤ 16 上限）
            var cols = Panel.widgetManager.instanceCols(instanceId)
            var rows = Panel.widgetManager.instanceRows(instanceId)
            var capacity = Math.max(1, cols * rows)
            maxSelect = Math.max(1, Math.min(capacity - list.length,
                                             16 - list.length))
        }
        root.positionPopup(appPickerDialog, -1)
        appPickerDialog.openFor(instanceId, index, current, maxSelect, list.slice())
    }

    // 二级面板确认后的回写：替换槽位取首项；追加模式逐项加入（防重复、上限 16）
    function applyAppPick(instanceId, index, desktopIdList) {
        if (Panel.widgetManager.instanceIds().indexOf(instanceId) < 0)
            return
        if (!Array.isArray(desktopIdList) || desktopIdList.length === 0)
            return
        var cfg = Panel.widgetManager.instanceConfig(instanceId)
        var list = root.asAppList(cfg ? cfg.launchers : undefined).slice()
        if (index >= 0 && index < list.length) {
            list[index] = String(desktopIdList[0])
        } else {
            var capCols = Panel.widgetManager.instanceCols(instanceId)
            var capRows = Panel.widgetManager.instanceRows(instanceId)
            var listCap = Math.max(1, capCols * capRows)   // 继承当前卡片容量
            for (var j = 0; j < desktopIdList.length; ++j) {
                var id = String(desktopIdList[j])
                if (id.length === 0 || list.indexOf(id) >= 0)
                    continue
                if (list.length >= listCap)
                    break
                list.push(id)
            }
        }
        Panel.widgetManager.saveInstanceConfig(instanceId, { "launchers": list })
    }

    // ===== 窗口基础配置（与通知中心一致的尺寸与样式） =====

    // 与通知中心一致的尺寸：内容宽 360 + 左右各 10 padding
    property int contentPadding: 10
    property int contentWidth: 360

    // 边距绑定必须声明在 visible 之前：组件完成阶段按声明顺序求值绑定，
    // 先求值边距（初值即 contentPadding，见 DockMarginHelper）再求值 visible，
    // 保证窗口首次映射时 DLayerShellWindow 边距已非 0——否则 X11 模拟层以 0 边距
    // 计算几何、Wayland 首帧提交 0 边距状态，面板首次打开被拉满全高（上下边距为 0）。
    DLayerShellWindow.topMargin: dockMargin.topMargin
    DLayerShellWindow.rightMargin: dockMargin.rightMargin
    DLayerShellWindow.bottomMargin: dockMargin.bottomMargin

    // 显示 = 用户显隐状态 且 未处于任何避让态。MMV/外部面板避让期间 Panel.visible
    // 不变（DConfig/托盘高亮不动），退出信号置对应 avoided=false 后自动回归。
    visible: Panel.visible && !Panel.multitaskAvoided && !Panel.panelAvoided
    // flags 刻意不含 Qt.FramelessWindowHint：Qt 对带 Frameless 的窗口写 _MOTIF_WM_HINTS 时
    // 不设置 MWM_HINTS_FUNCTIONS 位（functions 恒为 MWM_FUNC_ALL），kwin 据此判定窗口
    // 可最大化（isMaximizable()=true），首次映射高度达到工作区时被垂直最大化（y=0、
    // 上下边距为 0）并被钉住。改加 Min/Close 按钮 hint（不含 Maximize）后 Qt 会写出
    // functions=MOVE|RESIZE|MINIMIZE|CLOSE（含 FUNCTIONS 位、无 MAXIMIZE），kwin 判定
    // 不可最大化，从根源杜绝拉伸。无边框外观由 DWindow（_DEEPIN_SCISSOR_WINDOW）与
    // kwin 对 Notification/Dock 类型窗口不装饰保证，与通知中心（flags: Qt.Tool）一致。
    flags: Qt.Tool | Qt.WindowMinimizeButtonHint | Qt.WindowCloseButtonHint
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
            // 每次显示都重新取得 dock 对象并重启**有界**取对象轮询：dock 代理
            // 异步就绪可能晚于窗口创建，DS.applet() 返回值又不可跟踪。边距数值
            // 本身已由 DockMarginHelper 里的绑定跟踪，无需靠轮询维持。
            dockMargin.restart()
        }
    }
    Component.onCompleted: {
        if (Qt.platform.pluginName === "xcb") {
            applyLayerFlags()
        }
        updateGridPositions()
        dockMargin.restart()
    }
    function applyLayerFlags() {
        // X11 下用 flags 直接表达层级：置顶 = WindowStaysOnTopHint（_NET_WM_STATE_ABOVE，
        // kwin 置顶），置底 = WindowStaysOnBottomHint（可被普通窗口覆盖）。
        // 不依赖 X11 LayerShellEmulation 的 layer→窗口类型映射：该映射只在 layerChanged
        // 信号时应用，窗口 hide/show 重建原生窗口后不会重新执行（QWindow 对象不变时
        // DLayerShellWindow 与模拟器都不会重建），导致窗口类型/层级丢失。
        // 注意：setFlags 会触发 QXcbWindow 按 flags 重算 _NET_WM_WINDOW_TYPE
        // （Qt.Tool → UTILITY + NORMAL），覆盖模拟层设置的 Notification/Dock 类型，
        // kwin 会把面板当普通窗口垂直最大化（首次打开上下边距为 0）——窗口类型由
        // C++ WindowGuard::enforceWindowType() 在每次 setFlags 后恢复（置顶
        // =Notification、置底=Dock），本函数只负责 flags。
        // Wayland 下本函数不调用（合成器按 layer 管理），flags 无副作用。
        root.flags = layerIsBottom
            ? Qt.WindowStaysOnBottomHint | Qt.Tool
              | Qt.WindowMinimizeButtonHint | Qt.WindowCloseButtonHint
            : Qt.WindowStaysOnTopHint | Qt.Tool
              | Qt.WindowMinimizeButtonHint | Qt.WindowCloseButtonHint
    }

    // 与任务栏间距：边距是读 dock 属性的绑定（dock 一变即重算），
    // DockMarginHelper 只用有界轮询取得 dock applet 对象；输出属性供本窗口绑定消费
    Components.DockMarginHelper {
        id: dockMargin
        screenRef: root.screen
        contentPadding: root.contentPadding
    }
    width: contentWidth + contentPadding * 2

    // 置顶：Overlay 层（在所有窗口之上）；置底：Buttom 层（可被普通窗口覆盖）
    DLayerShellWindow.layer: Panel.pinned
        ? DLayerShellWindow.LayerOverlay : DLayerShellWindow.LayerButtom
    // 不向合成器声明排除区域：X11 下 exclusionZone 会被 LayerShellEmulation 转成
    // _NET_WM_STRUT_PARTIAL（默认 0 也会生成 0 宽 strut），实测带 strut 的窗口会被
    // kwin 当作工作区保留窗口特殊放置（首次映射被拉伸到全高、上下边距为 0）；
    // Wayland 下 exclusionZone 也会影响其他 layer-shell 窗口；而 dde-desktop 的
    // 桌面图标区域只按 dock 的 frontendWindowRect 计算、不读工作区，故 exclusionZone
    // 对图标避让无效。置底时仅保留 LayerButtom 层语义，不声明排除区域。
    DLayerShellWindow.exclusionZone: Qt.platform.pluginName === "wayland" ? 0 : -1
    DLayerShellWindow.anchors: DLayerShellWindow.AnchorRight
        | DLayerShellWindow.AnchorTop | DLayerShellWindow.AnchorBottom
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

                // 系统圆角遮罩：滚动内容按窗口圆角裁剪，滚动条一并入层
                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: gridFlickable.width
                        height: gridFlickable.height
                        radius: DTK.platformTheme.windowRadius
                    }
                }

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
                        delegate: Components.WidgetHostItem {
                            instanceId: modelData
                            gridX: root.cellX(modelData)
                            gridY: root.cellY(modelData)
                            cols: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceCols(modelData)
                            }
                            rows: {
                                let version = root.layoutVersion
                                return Panel.widgetManager.instanceRows(modelData)
                            }
                            cellWidth: root.cellWidth
                            cellSpacing: root.cellSpacing
                            cellSpacingY: root.cellSpacingY
                            cellHeight: root.cellHeight
                            cardLabelHeight: root.cardLabelHeight
                            cardLabelGap: root.cardLabelGap
                            dimmed: root.dragging && modelData === root.dragInstanceId
                            panelDragging: root.dragging
                            dragSurface: gridCanvas
                            menuSurface: root.contentItem

                            // 拖拽事件：坐标已在网格画布空间
                            onDragStartRequested: function(host, x, y) {
                                root.startDrag(host, x, y)
                            }
                            onDragMoveRequested: function(host, x, y) {
                                root.updateDrag(x, y)
                            }
                            onDragEndRequested: function(host) {
                                root.endDrag()
                            }
                            // 右键菜单：坐标已在窗口内容区空间
                            onContextMenuRequested: function(x, y) {
                                root.openWidgetMenu(instanceId, y)
                            }
                        }
                    }

                    // 拖放预览：跟随指针的组件快照 + 有效/无效边框
                    Item {
                        id: dragPreview
                        visible: false
                        z: 10
                        width: root.dragCols * cellWidth + (root.dragCols - 1) * cellSpacing
                        height: root.dragRows * cellHeight + (root.dragRows - 1) * cellSpacingY
                        // 本次拖拽的首个位置赋值必须瞬移：Behavior 若在此刻生效，
                        // 预览会从上一次拖拽的停留点（面板首次拖拽为 0,0）补间飞向
                        // 指针，方向随历史变化——即"莫名从四个方向飞入"。
                        // snapToPointer 期间关闭跟随动画，由 startDrag 一次性写入
                        // 抓取位置后立即恢复平滑跟随。
                        property bool snapToPointer: false
                        // 拖拽预览平滑跟随指针，避免逐格硬跳
                        Behavior on x {
                            enabled: !dragPreview.snapToPointer
                            SmoothedAnimation {
                                velocity: 1000
                                reversingMode: SmoothedAnimation.Immediate
                            }
                        }
                        Behavior on y {
                            enabled: !dragPreview.snapToPointer
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
            onClicked: {
                // 与右键菜单/托盘入口一致：先按触发位置（按钮中心）重定位弹窗，
                // 让二级面板趋向鼠标指针所在高度，而非默认贴面板顶部。
                var c = addButton.mapToItem(root.contentItem,
                                            addButton.width / 2, addButton.height / 2)
                root.openPanelPopup(addPopup, c.y)
            }
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
                { "cols": 4, "rows": 1, "label": qsTr("Long") + " 4×1" },
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

    // "选择程序"三级面板（卡片内"+"触发时使用；确认后按当前编辑目标回写实例配置）
    Components.AppPickerDialog {
        id: appPickerDialog

        onAppPicked: function(desktopIdList) {
            root.applyAppPick(appPickerDialog.instanceId,
                              appPickerDialog.editIndex, desktopIdList)
        }
    }

    // 小组件经 WidgetHost 请求打开三级面板（应用快捷启动器卡片内"+"）
    Connections {
        target: WidgetHost
        function onOpenAppPickerRequested(instanceId, index) {
            root.openAppPickerFor(instanceId, index)
        }
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
        // 任一避让开始（MMV / 外部面板）：收起全部二级弹窗。判断用聚合避让态，
        // 退出某一避让而另一仍在时不误开（closeAllPopups 只关不开）。
        function onMultitaskAvoidedChanged() {
            if (Panel.multitaskAvoided || Panel.panelAvoided)
                root.closeAllPopups()
        }
        function onPanelAvoidedChanged() {
            if (Panel.multitaskAvoided || Panel.panelAvoided)
                root.closeAllPopups()
        }
    }

    // ===== 添加小组件弹出面板 =====
    AddWidgetPopup {
        id: addPopup
    }
}
