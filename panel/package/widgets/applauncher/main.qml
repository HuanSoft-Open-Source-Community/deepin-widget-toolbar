// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：应用快捷启动器（默认长条 4×1，最多 16 个应用）。
// 单元 = 1×1 正方形（系统圆角、无边框线），一个单元一个软件；
// 显示数量随规格容量动态：小 1 / 中 4 / 长 4 / 宽 8 / 大 16，
// 已配置应用不足容量时末位显示"+"（打开三级程序选择面板）。
// 桌面条目/图标/默认程序/启动全部经宿主 DesktopApps 代理（与 dde-shell 同源）。
Components.WidgetCard {
    id: root

    // 配置真相源：直读宿主 Panel.widgetManager.instanceConfig，不依赖 widgetConfig
    // 注入/推送链路（该链路对本卡曾静默失效：配置落盘成功但卡片不刷新，
    // 表现为只有"+"、底色等设置不生效）。任何 instanceConfigChanged 都整包
    // 刷新 cfg 快照，使应用列表、种子标记与全部样式设置即时上屏。
    property var cfg: ({})
    readonly property bool cfgLoaded: root.cfg && ("launchers" in root.cfg)

    // 部分 C++ 返回路径把 QVariantList 包装成"类数组对象"而非真 JS 数组
    //（实测 instanceConfig 直读路径 Array.isArray 为 false），这里统一做容错提取
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

    property var launchers: root.asAppList(root.cfg.launchers)
    property bool seeded: root.cfg._launchersSeeded === true
    property bool immersiveMode: root.cfg.immersiveMode === true
    property bool showLabels: root.cfg.showLabels !== undefined
        ? root.cfg.showLabels : true
    transparentBackground: root.cfg.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        root.cfg.backgroundColor, "#660066")
    property color labelColor: Components.ColorUtils.resolveColor(
        root.cfg.labelColor, "#ffffff")
    property color unitColor: Components.ColorUtils.resolveColor(
        root.cfg.unitBackgroundColor, "#ffffff")

    function reloadConfig() {
        if (root.instanceId.length === 0)
            return
        root.cfg = Panel.widgetManager.instanceConfig(root.instanceId)
        console.warn("[applauncher] reload", root.instanceId.slice(0, 8),
                    "launchers", root.launchers.length,
                    "rawType", typeof root.cfg.launchers,
                    "rawIsArray", Array.isArray(root.cfg.launchers),
                    "seeded", root.seeded)
        root.trySeedDefaults()
    }

    // 实例上下文（instanceId）经宿主 Binding 注入可能晚于 Component.onCompleted
    onInstanceIdChanged: root.reloadConfig()
    Component.onCompleted: root.reloadConfig()

    // 任何配置保存（设置面板/选择面板/本卡种子）都会触发本卡刷新
    Connections {
        target: Panel.widgetManager
        function onInstanceConfigChanged(instanceId) {
            if (instanceId === root.instanceId)
                root.reloadConfig()
        }
    }

    // ===== 几何 =====
    readonly property int unitCols: Math.max(1, root.hostCols)
    readonly property int unitRows: Math.max(1, root.hostRows)
    readonly property int capacity: root.unitCols * root.unitRows
    // 委托池固定为最大容量：尺寸切换只改变几何/可见性，
    // 不反复销毁重建委托，配合位置动画让变化平滑
    readonly property int maxUnits: 16
    readonly property int visibleApps: Math.min(root.launchers.length, root.capacity)
    readonly property bool hasAddUnit: root.launchers.length < root.capacity
    readonly property int cellsUsed: root.visibleApps + (root.hasAddUnit ? 1 : 0)
    readonly property int innerPad: 6
    // 方格边长：先按纵向基准间距约束（正方形单元高度决定大小）
    readonly property int baseSpacing: 8
    readonly property real contentW: Math.max(1, width - root.margin * 2)
    readonly property real contentH: Math.max(1, height - root.margin * 2)
    // 与 DialGrid 同款：边长/原点全部用连续实数，宿主尺寸动画逐帧驱动，
    // 不做取整（取整会造成像素级步进与抖动）
    readonly property real unitSide: Math.max(1, Math.min(
        (root.contentW - 2 * root.innerPad - (root.unitCols - 1) * root.baseSpacing)
            / root.unitCols,
        (root.contentH - 2 * root.innerPad - (root.unitRows - 1) * root.baseSpacing)
            / root.unitRows))
    // 横向余量分配：先以间距吸收（8~24px 适中），剩余均分到左右两侧，
    // 避免长条卡片右侧留大块空白；多行时纵向同理
    readonly property real extraX: Math.max(0, root.contentW - 2 * root.innerPad
        - root.unitCols * root.unitSide)
    readonly property real gapX: root.unitCols > 1
        ? Math.min(24, Math.max(6, root.extraX / (root.unitCols - 1))) : 0
    readonly property real gridWidth: root.unitCols * root.unitSide
        + (root.unitCols - 1) * root.gapX
    readonly property real xOrigin: root.innerPad
        + Math.max(0, (root.contentW - 2 * root.innerPad - root.gridWidth) / 2)
    readonly property real extraY: Math.max(0, root.contentH - 2 * root.innerPad
        - root.unitRows * root.unitSide)
    readonly property real gapY: root.unitRows > 1
        ? Math.min(24, Math.max(6, root.extraY / (root.unitRows - 1))) : 0
    readonly property real gridHeight: root.unitRows * root.unitSide
        + (root.unitRows - 1) * root.gapY
    readonly property real yOrigin: root.innerPad
        + Math.max(0, (root.contentH - 2 * root.innerPad - root.gridHeight) / 2)
    // 标签放得下才显示：小卡（1×1）与过小单元自动隐去，仅保留图标；
    // 沉浸模式不显示标签（透明模式下文字改主题自适应色）
    readonly property bool labelsUsable: root.showLabels && !root.immersiveMode
        && root.capacity > 1 && root.unitSide >= 46
    readonly property real labelPixel: root.labelsUsable
        ? Math.max(9, Math.min(11, root.unitSide * 0.14)) : 0
    // 标签画在方块下缘之外（落在卡片底色上）：有标签时方块缩矮留出标签行
    readonly property real tilePixel: Math.max(1, root.unitSide - root.labelPixel)
    readonly property real iconPixel: Math.max(16, Math.min(
        root.unitSide * 0.66, Math.max(18, root.tilePixel - 10)))
    // 添加单元"+"的矢量十字尺寸/臂宽（根级常量，随单元边长缩放）
    readonly property real plusSize: Math.max(18, Math.round(root.unitSide * 0.46))
    readonly property real plusStroke: Math.max(2.0, root.plusSize * 0.16)

    // 图标渲染请求像素：与显示尺寸/动画解耦的固定值。尺寸切换瞬间几何会按
    // "旧卡片尺寸 × 新列数"产生瞬时大格（大→中第一帧格边可冲到 ~170px），
    // 若请求像素跟随动画，每个量化档都会同步重渲染一次图标造成卡顿。
    // 固定单尺寸（覆盖瞬时最大显示与常见 DPR）→ 每图标只解码一次，缩放交给 QML
    readonly property int iconPxRequest: 192

    // 状态：悬停/按压反馈
    property int hoveredUnit: -1
    property int pressedUnit: -1

    // ===== 单元命中 =====
    function unitAt(x, y) {
        // 事件坐标相对组件左上角；单元网格位于卡片内容区（margin 外 + xOrigin/yOrigin 内）
        var gx = x - root.margin - root.xOrigin
        var gy = y - root.margin - root.yOrigin
        if (gx < 0 || gy < 0)
            return -1
        var col = Math.floor(gx / (root.unitSide + root.gapX))
        var row = Math.floor(gy / (root.unitSide + root.gapY))
        if (col < 0 || col >= root.unitCols || row < 0 || row >= root.unitRows)
            return -1
        return row * root.unitCols + col
    }

    // 首次预置默认程序（浏览器/终端/文本编辑器/邮箱）：
    // 只在该实例尚未预置且尚无任何用户配置时写入默认列表；若用户已通过
    // 选择面板添加过应用（launchers 非空）则只补 _launchersSeeded 标记，
    // 避免默认种子晚于用户选择、把用户列表覆盖回去。
    function trySeedDefaults() {
        if (root.seeded || root.instanceId.length === 0 || !root.cfgLoaded)
            return
        var existing = root.launchers
        if (Array.isArray(existing) && existing.length > 0) {
            WidgetHost.saveConfig(root.instanceId, { "_launchersSeeded": true })
            return
        }
        var ids = DesktopApps.defaultAppIds()
        var resolved = []
        for (var i = 0; i < ids.length; ++i) {
            if (String(ids[i]).length > 0 && resolved.indexOf(ids[i]) < 0)
                resolved.push(String(ids[i]))
        }
        console.warn("[applauncher] seed attempt resolved", JSON.stringify(resolved),
                    "librarySize", DesktopApps.entries.length)
        if (resolved.length === 0) {
            // 应用库未就绪/默认解析暂空：随事件重试，另加有界轮询兜底
            root.startSeedPolling()
            return
        }
        var saved = WidgetHost.saveConfig(root.instanceId, {
            "launchers": resolved,
            "_launchersSeeded": true
        })
        console.warn("[applauncher] seed save result:", saved)
    }

    // 有界轮询兜底：默认解析短暂为空时每 1.5s 重试（最多 10 次），
    // 一旦成功或用户已配置立即停止
    property int seedPollCount: 0
    Timer {
        id: seedPollTimer
        interval: 1500
        repeat: true
        onTriggered: {
            root.seedPollCount++
            if (root.seedPollCount > 10) {
                stop()
                return
            }
            root.trySeedDefaults()
            if (root.seeded)
                stop()
        }
    }
    function startSeedPolling() {
        if (!seedPollTimer.running && root.seedPollCount <= 10)
            seedPollTimer.start()
    }
    onSeededChanged: {
        if (root.seeded && seedPollTimer.running)
            seedPollTimer.stop()
    }

    // 默认程序解析需等应用库就绪；条目频繁变化时合并重试（含 gsettings 只跑一次）
    Timer {
        id: seedRetryTimer
        interval: 400
        onTriggered: root.trySeedDefaults()
    }

    function scheduleSeedRetry() {
        if (!root.seeded && root.instanceId.length > 0 && !seedRetryTimer.running)
            seedRetryTimer.start()
    }

    Connections {
        target: DesktopApps
        function onEntriesChanged() { root.scheduleSeedRetry() }
        function onAvailableChanged() { root.scheduleSeedRetry() }
    }

    // 宿主拖放层转发：命中反馈与点击动作（点击=启动/打开选择面板）
    function handleHostPressed(x, y) {
        root.pressedUnit = root.unitAt(x, y)
    }

    function handleHostReleased(x, y) {
        root.pressedUnit = -1
        root.hoveredUnit = root.unitAt(x, y)
    }

    function handleHostClick(x, y) {
        var unit = root.unitAt(x, y)
        root.hoveredUnit = unit
        if (unit < 0)
            return
        console.warn("[applauncher] click unit", unit, "apps", root.visibleApps)
        if (unit < root.visibleApps) {
            DesktopApps.launch(String(root.launchers[unit]))
        } else if (root.hasAddUnit) {
            WidgetHost.requestOpenAppPicker(root.instanceId, -1)
        }
    }

    function handleHostHover(x, y) {
        root.hoveredUnit = (x < 0 || y < 0) ? -1 : root.unitAt(x, y)
    }

    // ===== 单元 =====
    Repeater {
        model: root.maxUnits

        delegate: Item {
            required property int index

            visible: index < root.cellsUsed
            x: root.xOrigin + (index % root.unitCols) * (root.unitSide + root.gapX)
            y: root.yOrigin + Math.floor(index / root.unitCols)
               * (root.unitSide + root.gapY)
            width: root.unitSide
            height: root.unitSide

            // 启动器单元：正方形、系统圆角、无边框线（标签在方块下方，方块让出标签行）
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: root.tilePixel
                height: root.tilePixel
                visible: index < root.visibleApps
                    && !root.immersiveMode && !root.effectiveTransparent
                radius: DTK.platformTheme.windowRadius
                color: root.unitColor
                scale: (root.pressedUnit === index) ? 0.94 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
            }

            // 图标（位于方块内居中；无方块时整体居中于单元）
            Image {
                width: root.iconPixel
                height: root.iconPixel
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(2, (root.tilePixel - root.iconPixel) / 2)
                sourceSize.width: root.iconPxRequest
                sourceSize.height: root.iconPxRequest
                visible: index < root.visibleApps
                source: {
                    if (index >= root.visibleApps)
                        return ""
                    var launcherId = String(root.launchers[index])
                    var iconName = DesktopApps.iconNameOf(launcherId)
                    return DesktopApps.iconSource(
                        iconName.length > 0 ? iconName : launcherId,
                        root.iconPxRequest)
                }
                smooth: true
                opacity: (root.pressedUnit === index) ? 0.7 : 1.0
                Behavior on opacity {
                    NumberAnimation { duration: 90 }
                }
            }

            // 标签（可选，颜色独立可配；位于方块下方）
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.tilePixel
                width: root.unitSide
                height: root.labelPixel
                visible: index < root.visibleApps && root.labelsUsable
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                text: {
                    if (index >= root.visibleApps)
                        return ""
                    var n = DesktopApps.nameOf(String(root.launchers[index]))
                    return n.length > 0 ? n : String(root.launchers[index])
                }
                elide: Text.ElideRight
                font.pixelSize: root.labelPixel
                color: root.effectiveTransparent
                    ? root.themeTextColor : root.labelColor
                opacity: 0.9
            }

            // 添加单元"+"：矢量十字绘制（两段圆头矩形），随尺寸原生渲染、
            // 无位图缩放/图层重采样，任何尺寸都保持清晰锐利；颜色随标签/主题
            Item {
                visible: index === root.visibleApps && root.hasAddUnit
                anchors.fill: parent

                Item {
                    anchors.centerIn: parent
                    width: root.plusSize
                    height: root.plusSize

                    // 横臂
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.plusSize
                        height: root.plusStroke
                        radius: Math.max(1, root.plusStroke / 2)
                        color: root.effectiveTransparent
                            ? root.themeTextColor : root.labelColor
                        antialiasing: true
                    }

                    // 竖臂
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.plusStroke
                        height: root.plusSize
                        radius: Math.max(1, root.plusStroke / 2)
                        color: root.effectiveTransparent
                            ? root.themeTextColor : root.labelColor
                        antialiasing: true
                    }
                }

                // 点击反馈 + 命中提示（host 事件层负责最终点击）
                Rectangle {
                    anchors.fill: parent
                    radius: DTK.platformTheme.windowRadius
                    color: root.hoveredUnit === index
                        ? (DTK.themeType === ApplicationHelper.DarkType
                            ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                        : "transparent"
                    scale: (root.pressedUnit === index) ? 0.94 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
