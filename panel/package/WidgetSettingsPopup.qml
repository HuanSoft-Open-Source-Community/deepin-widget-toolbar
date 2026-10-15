// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "widgets/components" as Components
import "widgets/components/dialslogic.js" as DialsLogic
import "widgets/components/locklogic.js" as LockLogic

// 单个小组件实例的配置面板：复用 PanelPopup/PopupHeader，
// 根据 WidgetManager 返回的 settings schema 动态生成控件并即时保存。
PanelPopup {
    id: control

    property string instanceId: ""
    property string widgetId: ""
    property var schema: []
    property var visibleSchema: []
    property var values: ({})
    property var zoneOptions: []
    property var usedZones: []
    property var playerOptions: []
    property string editingColorKey: ""
    property string editingDialKey: ""
    property int editingDialIndex: -1
    property string editingDialField: ""
    // 启动器单元（applauncher）三级选择面板的编辑目标（launcherList 行）
    property string editingLauncherKey: ""
    property int editingLauncherIndex: -1
    // 图片选择对话框的编辑目标（image 行）
    property string editingImageKey: ""
    // 本实例的数据目录（image 行缩略图/相对路径的基准，与宿主注入小组件的
    // dataDir 同一来源：widgetDataDir(instanceWidgetId)，同 WidgetHostItem）
    readonly property string dataDir: Panel.widgetManager.widgetDataDir(
        Panel.widgetManager.instanceWidgetId(control.instanceId))
    // 设置面板会话代号：打开/重建时 +1，launcherList 行据此做拖拽状态复位与
    // 尺寸容量重同步（函数式容量绑定不会自己跟踪 instanceCols/Rows 的变化）
    property int launcherEditSession: 0
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-widget-settings"

    width: 360
    height: 520

    onPopupVisibleChanged: {
        // 本弹窗隐藏时同收其子级（色卡/三级应用选择），避免残留在桌面。
        // 注意：这里绝不能关 imageDialog——它是独立窗口的
        // QtQuick.Dialogs.FileDialog，弹出后本 PanelPopup 的 popupWindow 立即
        // 失焦，dde-shell 的 PanelPopup 随之失焦自关闭 → popupVisible 变 false
        // → 本处理器会把刚打开的对话框立刻关掉（表现为"文件对话框打不开"）。
        // FileDialog 由用户自行确认/取消关闭，无需随设置面板收尾。
        if (!popupVisible) {
            colorDialog.close()
            launcherPicker.close()
        }
    }

    function openFor(instance) {
        control.instanceId = instance
        control.widgetId = Panel.widgetManager.instanceWidgetId(instance)
        control.schema = Panel.widgetManager.widgetSettingsSchema(control.widgetId)
        control.values = Panel.widgetManager.instanceConfig(instance)
        if (control.needsTimezones()) {
            control.zoneOptions = Timezones.zoneOptions()
            control.usedZones = WidgetHost.usedZones(control.instanceId)
        } else {
            control.zoneOptions = []
            control.usedZones = []
        }
        if (control.needsPlayers())
            control.playerOptions = MediaPlayers.players
        else
            control.playerOptions = []
        control.rebuildVisibleSchema()
        control.launcherEditSession++
        settingsScroll.interactive = true   // 复位上一会话可能的拖拽滚动锁
        control.open()
    }

    function needsTimezones() {
        for (var i = 0; i < control.schema.length; ++i) {
            if (control.schema[i].type === "timezoneList")
                return true
        }
        return false
    }

    function needsPlayers() {
        for (var i = 0; i < control.schema.length; ++i) {
            if (control.schema[i].type === "player")
                return true
        }
        return false
    }

    // 透明模式（全局卡片透明或本卡 transparentBackground 任一生效）下不再
    // 生效的颜色配置键：卡片底/内部区域底色改画半透明叠层、文字改主题自适应
    // 色（themeTextColor），对应设置行从面板隐藏。逐卡片对照渲染分支核实：
    //   - 卡片底/区域底：各卡 backgroundColor 与日历标题/星期头、便签标题/
    //     内容底（todo）——透明分支不再绘制或改画叠层；
    //   - 文字色：calendar/systemmonitor/todo/worldtime 的文字在透明下由
    //     themeTextColor 接管（clock 的 textColor 仅模拟表盘数字使用，保留）；
    //   - calendar gridColor、todo lineColor：透明下不绘制；
    //   - applauncher unitBackgroundColor：单元底色矩形整体隐藏。
    // 指针/高亮/条形等内容色（dialColor、手色、highlightColor、barColor 等）
    // 透明下仍生效，一律保留。第三方小组件查表 miss 不受影响。
    readonly property var transparentHiddenColors: ({
        applauncher: ["backgroundColor", "labelColor", "unitBackgroundColor"],
        clock: ["backgroundColor", "dialBackgroundColor"],
        calendar: ["backgroundColor", "textColor", "titleBackgroundColor",
            "titleTextColor", "weekdayBackgroundColor", "weekdayTextColor",
            "gridColor"],
        systemmonitor: ["backgroundColor", "textColor", "titleTextColor",
            "labelTextColor", "valueTextColor"],
        player: ["backgroundColor"],
        todo: ["textColor", "titleBackgroundColor", "titleTextColor",
            "contentBackgroundColor", "lineColor"],
        worldtime: ["backgroundColor", "textColor", "dialBackgroundColor"],
        lyrics: ["backgroundColor"],
        spectrum: ["backgroundColor"]
    })

    function rebuildVisibleSchema() {
        var cols = Panel.widgetManager.instanceCols(control.instanceId)
        // 全局卡片透明模式或本卡透明开关任一生效即视为透明
        var transparent = Panel.cardTransparent === true
            || control.values.transparentBackground === true
        var transparentHidden = transparent
            ? (control.transparentHiddenColors[control.widgetId] || [])
            : []
        // 全局透明开启时：内置卡片的单卡透明开关恒被全局覆盖（任一生效即
        // 为透明），开关无视觉效果，一并隐藏；第三方组件的卡片未必响应
        // 全局模式（hostCardTransparent 仅作用于 WidgetCard 系），其开关保留。
        var hideTransparentSwitch = Panel.cardTransparent === true
            && Panel.widgetManager.isBuiltin(control.widgetId)
        var result = []
        for (var i = 0; i < control.schema.length; ++i) {
            var item = control.schema[i]
            // “_”前缀为内部键（如首启预置标记），不进入设置面板
            if (String(item.key).charAt(0) === "_")
                continue
            if (control.widgetId === "systemmonitor" && item.key === "dualColumn"
                && cols < 4) {
                continue
            }
            if (control.widgetId === "player" && item.key === "lockedPlayer"
                && control.values.playerMode !== "locked") {
                continue
            }
            // 沉浸模式：标签与启动器底色相关设置不再展示（视觉同步隐藏）
            if (control.widgetId === "applauncher"
                && control.values.immersiveMode === true
                && (item.key === "showLabels" || item.key === "labelColor"
                    || item.key === "unitBackgroundColor")) {
                continue
            }
            // 透明模式：失效的颜色设置行不再展示（与沉浸模式隐藏取并集）
            if (transparentHidden.indexOf(item.key) >= 0) {
                continue
            }
            // 全局透明下内置卡片的单卡透明开关同样失效，一并隐藏
            if (hideTransparentSwitch && item.key === "transparentBackground") {
                continue
            }
            result.push(item)
        }
        control.visibleSchema = result
    }

    function commit(key, value) {
        // 重新赋值整个 values 对象，保证依赖 control.values 的绑定（如
        // timezoneList 的行模型）在保存后重新求值
        var prev = control.values
        var next = {}
        for (var k in prev)
            next[k] = prev[k]
        next[key] = value
        // lockWhen 声明式联动引擎（宿主 API 1.11）：纯 schema 声明驱动、
        // 不感知任何键名/组件名；无声明时 applyLocks 是零操作（不产生新键、
        // 不改值，保存路径与既往完全一致）。非法声明由引擎静默跳过，
        // 面板包装层负责校验与去重告警（见 warnLockDecl）。
        for (var i = 0; i < control.schema.length; ++i) {
            if (control.schema[i].lockWhen !== undefined) {
                var bad = LockLogic.validateLock(control.schema, control.schema[i].key)
                if (bad !== "")
                    control.warnLockDecl(String(control.schema[i].key), bad)
            }
        }
        LockLogic.applyLocks(control.schema, prev, next, key)
        control.values = next
        Panel.widgetManager.saveInstanceConfig(control.instanceId, next)
        if ((control.widgetId === "player" && key === "playerMode")
            || (control.widgetId === "applauncher" && key === "immersiveMode")
            || key === "transparentBackground")
            control.rebuildVisibleSchema()
    }

    // lockWhen 校验告警去重缓存：按面板实例每目标键只告警一次——
    // 滑块每次拖动都会 commit，非法声明若逐次告警会刷屏
    property var lockWarned: ({})

    function warnLockDecl(targetKey, reason) {
        if (control.lockWarned[targetKey] === undefined) {
            control.lockWarned[targetKey] = true
            console.warn("WidgetSettings: invalid lockWhen declaration on",
                         control.widgetId, "key", targetKey, "-", reason)
        }
    }

    // 表盘列表编辑：纯计算在 dialslogic.js，这里只做包装与落盘
    function openCustomColor(key, colorText) {
        control.editingColorKey = key
        control.editingDialKey = ""
        colorDialog.avoidOffsetX = launcherPicker.visible ? launcherPicker.width + 8 : 0
        colorDialog.openFor(String(colorText))
    }

    function openDialColor(key, index, field, colorText) {
        control.editingColorKey = ""
        control.editingDialKey = key
        control.editingDialIndex = index
        control.editingDialField = field
        colorDialog.avoidOffsetX = launcherPicker.visible ? launcherPicker.width + 8 : 0
        colorDialog.openFor(String(colorText))
    }

    function dialList(key) {
        return DialsLogic.dialList(control.values, key)
    }

    function rowOptions(key, index) {
        return DialsLogic.rowOptions(control.usedZones, control.values,
            control.zoneOptions, key, index)
    }

    function zoneIndex(key, index) {
        return DialsLogic.zoneIndex(control.usedZones, control.values,
            control.zoneOptions, key, index)
    }

    function addDial(key) {
        var list = DialsLogic.addDial(control.values, control.usedZones,
            control.zoneOptions, Timezones.systemTimezone, key)
        if (list)
            control.commit(key, list)
    }

    function removeDial(key, index) {
        var list = DialsLogic.removeDial(control.values, key, index)
        if (list)
            control.commit(key, list)
    }

    function setDialZone(key, index, zone) {
        var list = DialsLogic.setDialZone(control.usedZones, control.values,
            key, index, zone)
        if (list)
            control.commit(key, list)
    }

    function dialColorValue(key, index, field) {
        return DialsLogic.dialColorValue(control.values,
            DialsLogic.dialList(control.values, key), index, field)
    }

    function commitDialColor(key, index, field, value) {
        var list = DialsLogic.commitDialColor(control.values, key, index, field, value)
        if (list)
            control.commit(key, list)
    }

    // ===== 启动器单元列表（launcherList 行）=====

    // C++ QVariantList 经部分返回路径会变成"类数组对象"，Array.isArray 不成立，
    // 统一容错提取（与 applauncher 内 asAppList 同一规则）
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

    function launcherList(key) {
        return control.asAppList(control.values[key])
    }

    // 打开三级"选择程序"面板替换某槽位 / 追加新单元（上限 16）；
    // 若同级的色卡取色面板正打开，向左让位避免叠窗
    // 实例当前容量（剩余空位 = 容量 - 已配置数；容量即该尺寸能放的上限，≤ 16）
    function launcherCapacity() {
        var cols = Panel.widgetManager.instanceCols(control.instanceId)
        var rows = Panel.widgetManager.instanceRows(control.instanceId)
        return Math.max(1, cols * rows)
    }

    // 替换某槽位：三级面板单选该槽
    function openLauncherPicker(key, index) {
        var list = control.launcherList(key)
        if (index < 0 || index >= list.length)
            return
        control.editingLauncherKey = key
        control.editingLauncherIndex = index
        launcherPicker.avoidOffsetX = colorDialog.visible ? colorDialog.width + 8 : 0
        launcherPicker.openFor(control.instanceId, index, [String(list[index])], 1, [])
    }

    // 追加空位：三级面板可多选，上限 = 当前卡片剩余空位（容量上限随尺寸继承）
    function addLauncher(key) {
        var list = control.launcherList(key)
        var capacity = control.launcherCapacity()
        if (list.length >= capacity)
            return
        control.editingLauncherKey = key
        control.editingLauncherIndex = -1
        var remaining = Math.max(1, capacity - list.length)
        launcherPicker.avoidOffsetX = colorDialog.visible ? colorDialog.width + 8 : 0
        launcherPicker.openFor(control.instanceId, -1, [], remaining, list.slice())
    }

    // 恢复默认四应用（浏览器/终端/文本编辑器/邮箱）：
    // 按当前卡片容量裁剪（与卡片首启播种同一策略）——1×1 小卡只保留第一个
    function restoreDefaultLaunchers(key) {
        var ids = DesktopApps.defaultAppIds()
        var resolved = []
        for (var i = 0; i < ids.length; ++i) {
            if (String(ids[i]).length > 0 && resolved.indexOf(String(ids[i])) < 0)
                resolved.push(String(ids[i]))
        }
        if (resolved.length === 0)
            return
        var capacity = Math.max(1, control.launcherCapacity())
        if (resolved.length > capacity)
            resolved = resolved.slice(0, capacity)
        control.commit(key, resolved)
    }

    // 拖放排序：把 from 行的单元移动到 to 行位置（一次落盘，卡片即时重排）
    function reorderLaunchers(key, from, to) {
        var list = control.launcherList(key)
        if (from === to || from < 0 || from >= list.length
            || to < 0 || to >= list.length)
            return
        var moved = list.slice()
        var item = moved.splice(from, 1)[0]
        moved.splice(to, 0, item)
        control.commit(key, moved)
    }

    // 行拖放期间禁用滚动（防 Flickable 抢手势），结束恢复
    function beginRowDrag() {
        settingsScroll.interactive = false
    }
    function endRowDrag() {
        settingsScroll.interactive = true
    }

    // 三级面板确认：替换槽位取首项；追加模式逐项加入
    //（防重复、上限 = 当前卡片容量；多选上限已在面板层按剩余空位约束）
    function commitLauncherPicked(desktopIdList) {
        var key = control.editingLauncherKey
        if (key.length === 0 || !Array.isArray(desktopIdList))
            return
        var picked = []
        for (var i = 0; i < desktopIdList.length; ++i) {
            var id = String(desktopIdList[i])
            if (id.length > 0 && picked.indexOf(id) < 0)
                picked.push(id)
        }
        if (picked.length === 0)
            return
        var list = control.launcherList(key)
        var index = control.editingLauncherIndex
        var capacity = control.launcherCapacity()
        control.editingLauncherKey = ""
        control.editingLauncherIndex = -1
        if (index >= 0 && index < list.length) {
            list = list.slice()
            list[index] = picked[0]
        } else {
            list = list.slice()
            for (var j = 0; j < picked.length; ++j) {
                if (list.length >= capacity || list.indexOf(picked[j]) >= 0)
                    continue
                list.push(picked[j])
            }
        }
        control.commit(key, list)
    }

    function removeLauncher(key, index) {
        var list = control.launcherList(key).slice()
        if (index < 0 || index >= list.length)
            return
        list.splice(index, 1)
        control.commit(key, list)
    }

    // ===== 实例图片（image 行）=====

    // 缩略图 file:// URL 构造：整段编码后再还原 "/"，含空格/# 等特殊
    // 字符的文件名也能正确加载
    function imageUrl(relativePath) {
        var path = control.dataDir + "/" + relativePath
        return "file://" + encodeURIComponent(path).replace(/%2F/g, "/")
    }

    // 打开图片选择对话框（编辑目标 key 由 editingImageKey 记录）
    function openImagePicker(key) {
        control.editingImageKey = key
        imageDialog.open()
    }

    // 对话框确认：宿主复制进 <dataDir>/<instanceId>/ → 清理旧图 → 落盘
    // 新相对路径（经 commit，与其它行同一保存路径）。复制失败（来源
    // 不存在/后缀不支持等）时保持原值不动
    function commitPickedImage(fileUrl) {
        var key = control.editingImageKey
        control.editingImageKey = ""
        if (key.length === 0)
            return
        var previous = control.values[key] !== undefined
            && control.values[key] !== null ? String(control.values[key]) : ""
        var relative = WidgetHost.importInstanceImage(control.instanceId, String(fileUrl))
        if (relative.length === 0)
            return
        if (previous.length > 0 && previous !== relative)
            WidgetHost.removeInstanceImage(control.instanceId, previous)
        // 防呆：只回写图片路径、不切取图模式时，卡片（如 photoframe 的
        // sourceMode 仍是 bing*/url）evaluate 仍走网络取图 → 失败后显示
        // "网络不可用"，所选本地图片不显示。故按 schema 查找含 "local"
        // 选项的 enum 设置项（photoframe 即 sourceMode），当前值非 "local"
        // 时先切到 "local" 再写图片路径——先切模式后写路径，卡片两次
        // onWidgetConfigChanged 重评估都落在本地分支，全程不触发网络取图。
        // 纯 schema 驱动，不硬编码卡片/键名。
        for (var i = 0; i < control.schema.length; ++i) {
            var item = control.schema[i]
            if (item.type !== "enum")
                continue
            var options = item.options ? item.options : []
            var hasLocal = false
            for (var j = 0; j < options.length; ++j) {
                if (String(options[j].value) === "local") {
                    hasLocal = true
                    break
                }
            }
            if (!hasLocal || control.values[item.key] === "local")
                continue
            control.commit(item.key, "local")
        }
        control.commit(key, relative)
    }

    // 清除图片：删除实例目录内的旧图并落盘空串（未设置）
    function clearInstanceImage(key) {
        var previous = control.values[key] !== undefined
            && control.values[key] !== null ? String(control.values[key]) : ""
        if (previous.length > 0)
            WidgetHost.removeInstanceImage(control.instanceId, previous)
        control.commit(key, "")
    }

    // 自定义颜色取色弹窗（拆分自本面板）：编辑目标由 editing* 状态记录，
    // 确认/取消后清空；commit 与 commitDialColor 走本面板既有路径
    Components.ColorPickerDialog {
        id: colorDialog
        hostPopupWindow: control.popupWindow
        hostHeight: control.height

        onColorCommitted: function(colorText) {
            if (control.editingColorKey.length > 0) {
                control.commit(control.editingColorKey, colorText)
                control.editingColorKey = ""
            } else if (control.editingDialKey.length > 0) {
                control.commitDialColor(control.editingDialKey,
                    control.editingDialIndex, control.editingDialField, colorText)
                control.editingDialKey = ""
                control.editingDialIndex = -1
                control.editingDialField = ""
            }
        }
        onCanceled: {
            control.editingColorKey = ""
            control.editingDialKey = ""
            control.editingDialIndex = -1
            control.editingDialField = ""
        }
    }

    // 启动器单元的应用列表 —— 三级面板（应用快捷启动器，从二级设置面板唤起）：
    // 结构与取色器色卡同级（弹中弹：自建窗口锚定本设置弹窗，水平浮其左侧）。
    // 与色卡互相避让：打开一方前若对方正显示，向左让出对方宽度。
    Components.AppPickerLevel3 {
        id: launcherPicker
        hostPopupWindow: control.popupWindow
        hostHeight: control.height

        onAppPicked: function(desktopId) {
            control.commitLauncherPicked(desktopId)
        }
        onCanceled: {
            control.editingLauncherKey = ""
            control.editingLauncherIndex = -1
        }
    }

    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        // 图片选择对话框（image 行）：过滤宿主支持的图片格式，确认后经
        // WidgetHost 由宿主把沙箱外的来源文件复制进实例数据目录。
        // 必须作为内容卡片的子项：PanelPopup 的 default property 只接受可见
        // Item，直接挂根下会报 "Cannot assign object to list property popupContent"
        // 并使 WidgetSettingsPopup 类型整体不可用（面板无法加载）。
        FileDialog {
            id: imageDialog
            title: qsTr("Choose an image")
            // 窗口级模态：独立窗口弹出期间屏蔽宿主窗口的交互，避免焦点在
            // 对话框与设置面板之间来回切换导致对话框被意外收起
            modality: Qt.WindowModal
            nameFilters: [qsTr("Images") + " (*.png *.jpg *.jpeg *.bmp *.webp)"]
            onAccepted: control.commitPickedImage(selectedFile)
        }

        Connections {
            target: Panel.widgetManager
            // 尺寸/实例变化会改卡片容量，需让 launcherList 行会话重同步
            // （launcherCapacity() 是函数调用，靠 session 计数制造绑定依赖）
            function onInstancesChanged() {
                control.rebuildVisibleSchema()
                control.launcherEditSession++
            }
            function onLayoutChanged() {
                control.rebuildVisibleSchema()
                control.launcherEditSession++
            }
        }

        Connections {
            target: Timezones
            function onZoneOptionsChanged() {
                if (control.needsTimezones())
                    control.zoneOptions = Timezones.zoneOptions()
            }
        }

        Connections {
            target: MediaPlayers
            function onPlayersChanged() {
                if (control.needsPlayers())
                    control.playerOptions = MediaPlayers.players
            }
        }

        Connections {
            target: Panel
            // 面板设置切换全局卡片透明模式时，已打开的卡片设置面板即时
            // 增删透明下失效的颜色设置行
            function onCardTransparentChanged() {
                control.rebuildVisibleSchema()
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            PopupHeader {
                title: qsTr("Widget settings")
                onCloseRequested: control.close()
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: Panel.widgetManager.displayName(control.widgetId)
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.7
                elide: Text.ElideRight
                // 组件名截断时悬停显示全文
                Components.ElideTip { anchors.fill: parent }
            }

            Flickable {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                // 底部保留余量：设置项可滚动时最后一行不会紧贴可视区下缘，
                // 避免 DTK Switch 等控件底部因亚像素/DPR 取整被裁掉几行像素。
                contentHeight: settingsColumn.implicitHeight + 16

                // 系统圆角遮罩：滚动内容按弹窗圆角裁剪
                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: settingsScroll.width
                        height: settingsScroll.height
                        radius: DTK.platformTheme.windowRadius
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: vScrollBar
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                ColumnLayout {
                    id: settingsColumn
                    // 叠加式滚动条出现时会遮盖内容右缘：列宽为其让出滚动条宽 + 4px 间隙。
                    // 无循环绑定：vScrollBar.visible 只取决于 contentHeight 与 height，
                    // 与本列宽无关。
                    width: settingsScroll.width
                        - (vScrollBar.visible ? vScrollBar.width + 4 : 0)
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        visible: control.visibleSchema.length === 0
                        text: qsTr("This widget has no configurable options")
                        font: DTK.fontManager.t6
                        color: palette.windowText
                        opacity: 0.6
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: control.visibleSchema
                        delegate: Components.SettingsRow {
                            host: control
                        }
                    }
                }
            }
        }
    }
}
