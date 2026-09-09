// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import "widgets/components" as Components
import "widgets/components/dialslogic.js" as DialsLogic

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
    // 设置面板会话代号：打开/重建时 +1，launcherList 行据此做拖拽状态复位与
    // 尺寸容量重同步（函数式容量绑定不会自己跟踪 instanceCols/Rows 的变化）
    property int launcherEditSession: 0
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-widget-settings"

    width: 360
    height: 520

    onPopupVisibleChanged: {
        // 本弹窗隐藏时同收其子级（色卡/三级应用选择），避免残留在桌面
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

    function rebuildVisibleSchema() {
        var cols = Panel.widgetManager.instanceCols(control.instanceId)
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
            result.push(item)
        }
        control.visibleSchema = result
        // 尺寸/实例变化导致的重建同样触发 launcherList 会话重同步
        control.launcherEditSession++
    }

    function commit(key, value) {
        // 重新赋值整个 values 对象，保证依赖 control.values 的绑定（如
        // timezoneList 的行模型）在保存后重新求值
        var next = {}
        for (var k in control.values)
            next[k] = control.values[k]
        next[key] = value
        control.values = next
        Panel.widgetManager.saveInstanceConfig(control.instanceId, next)
        if ((control.widgetId === "player" && key === "playerMode")
            || (control.widgetId === "applauncher" && key === "immersiveMode"))
            control.rebuildVisibleSchema()
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
    // 容量放不下时只保留第一个（如 1×1 小卡）
    function restoreDefaultLaunchers(key) {
        var ids = DesktopApps.defaultAppIds()
        var resolved = []
        for (var i = 0; i < ids.length; ++i) {
            if (String(ids[i]).length > 0 && resolved.indexOf(String(ids[i])) < 0)
                resolved.push(String(ids[i]))
        }
        if (resolved.length === 0)
            return
        if (resolved.length > control.launcherCapacity())
            resolved = [resolved[0]]
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

        Connections {
            target: Panel.widgetManager
            function onInstancesChanged() { control.rebuildVisibleSchema() }
            function onLayoutChanged() { control.rebuildVisibleSchema() }
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
                    policy: ScrollBar.AsNeeded
                    anchors.right: parent.right
                }

                ColumnLayout {
                    id: settingsColumn
                    width: parent.width
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
