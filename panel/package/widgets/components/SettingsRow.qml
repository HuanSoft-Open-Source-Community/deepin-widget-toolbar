// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// 小组件配置面板的单行设置项（schema 驱动的 Repeater 委托，从配置面板拆分）：
// 按 type 分支渲染 boolean/enum/font/player/color/integer/string/launcherList/timezoneList；
// 所有回写经 host（配置面板）的 commit/openCustomColor/openLauncherPicker 等函数完成。
RowLayout {
    id: root

    // 宿主注入：modelData 由 Repeater 以属性方式注入（命名组件委托 +
    // required 属性时，隐式 modelData 上下文变量在绑定处不可用，见
    // WidgetSettingsPopup 的 Repeater）；host 由配置面板传入
    required property var modelData
    required property var host

    property string key: modelData.key
    property string type: modelData.type
    property var options: modelData.options ? modelData.options : []

    Layout.fillWidth: true
    spacing: 8

    Text {
        Layout.preferredWidth: 88
        visible: type !== "timezoneList" && type !== "launcherList"
        text: modelData.label ? modelData.label : modelData.key
        font: DTK.fontManager.t6
        color: palette.windowText
        elide: Text.ElideRight
    }

    Switch {
        Layout.fillWidth: true
        // DTK Switch 的 indicator 比控件隐式高度高；
        // 再多留 10px 安全高度，覆盖阴影、焦点描边与 DPR 取整。
        Layout.preferredHeight: Math.max(
            implicitHeight,
            (indicator ? indicator.implicitHeight : 0) + 10)
        visible: type === "boolean"
        checked: host.values[key] === true
        onToggled: host.commit(key, checked)
    }

    ComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        visible: type === "enum"
        model: options
        textRole: "label"
        currentIndex: {
            for (var i = 0; i < options.length; i++) {
                if (options[i].value === host.values[key])
                    return i
            }
            return 0
        }
        onActivated: function (i) {
            host.commit(key, options[i].value)
        }
    }

    ComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        visible: type === "font"
        editable: false
        model: Qt.fontFamilies()
        currentIndex: {
            var fonts = Qt.fontFamilies()
            var i = fonts.indexOf(host.values[key])
            return i >= 0 ? i : 0
        }
        onActivated: function (i) {
            var fonts = Qt.fontFamilies()
            if (i >= 0 && i < fonts.length)
                host.commit(key, fonts[i])
        }
    }

    ComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        visible: type === "player"
        enabled: host.playerOptions.length > 0
        model: host.playerOptions
        textRole: "name"
        currentIndex: {
            var current = host.values[key]
            for (var i = 0; i < host.playerOptions.length; i++) {
                if (host.playerOptions[i].service === current)
                    return i
            }
            return 0
        }
        onActivated: function (i) {
            if (i >= 0 && i < host.playerOptions.length)
                host.commit(key, host.playerOptions[i].service)
        }
    }

    Item {
        id: colorSelector
        Layout.fillWidth: true
        Layout.preferredHeight: colorSelector.flowContentHeight
            + 2 * colorSelector.flowPadding
        visible: type === "color"
        clip: true

        readonly property int swatchSize: 24
        readonly property int swatchSpacing: 6
        readonly property int flowPadding: 4
        readonly property int flowRightInset: 24
        readonly property int flowWidth: Math.max(
            swatchSize + swatchSpacing,
            host.width - 2 * 12 - 88 - 8
                - 2 * flowPadding - flowRightInset)
        readonly property int flowColumns: Math.max(1, Math.floor(
            (flowWidth + swatchSpacing)
                / (swatchSize + swatchSpacing)))
        readonly property int flowRows: Math.ceil(
            (options.length + 1) / flowColumns)
        readonly property int flowContentHeight:
            flowRows * swatchSize
                + (flowRows - 1) * swatchSpacing

        property string selectedValue: host.values[key] !== undefined
            ? String(host.values[key]) : ""

        function isKnownOption(value) {
            for (var i = 0; i < options.length; ++i) {
                if (String(options[i].value) === String(value))
                    return true
            }
            return false
        }

        // 定位并动画移动到当前选中项；自定义值没有预设色块时定位到 "+"
        function updateFromValue(value) {
            var known = isKnownOption(String(value))
            var target = null
            for (var i = 0; i < colorFlow.children.length; ++i) {
                var child = colorFlow.children[i]
                if (!child || !child.selectable)
                    continue
                if (known && child.colorValue === String(value)) {
                    target = child
                    break
                }
                if (!known && child.isCustomButton) {
                    target = child
                    break
                }
            }

            if (!target) {
                selectionRing.opacity = 0
                return
            }

            selectionRing.x = colorFlow.x + target.x - 3
            selectionRing.y = colorFlow.y + target.y - 3
            selectionRing.width = target.width + 6
            selectionRing.height = target.height + 6
            selectionRing.opacity = 1
        }

        onSelectedValueChanged: updateFromValue(selectedValue)
        Component.onCompleted: updateFromValue(selectedValue)

        Flow {
            id: colorFlow
            x: colorSelector.flowPadding
            y: colorSelector.flowPadding
            width: colorSelector.flowWidth
            height: colorSelector.flowContentHeight
            spacing: colorSelector.swatchSpacing

            Repeater {
                model: options
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    property bool selectable: true
                    property string colorValue: String(modelData.value)

                    width: 24
                    height: 24
                    radius: 12
                    // 空串色值 = “跟随主题色”（如频谱面板 barColor 缺省），
                    // 色块按当前主题高亮色渲染，避免空色显示为黑块
                    color: String(modelData.value).length > 0
                        ? modelData.value
                        : (DTK.themeType === ApplicationHelper.DarkType
                            ? "#4d8cff" : "#0081ff")
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                    transformOrigin: Item.Center
                    scale: swatchMouse.pressed ? 0.88 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            host.commit(key, modelData.value)
                            colorSelector.updateFromValue(
                                String(modelData.value))
                        }
                    }
                }
            }

            Rectangle {
                id: customColorButton

                property bool selectable: true
                property bool isCustomButton: true
                property string colorValue: ""

                width: 24
                height: 24
                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.25)
                transformOrigin: Item.Center
                scale: customColorMouse.pressed ? 0.88 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 13
                    color: palette.windowText
                }

                MouseArea {
                    id: customColorMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        var current = String(host.values[key] !== undefined
                            ? host.values[key] : "")
                        host.openCustomColor(key, current)
                    }
                }
            }
        }

        Rectangle {
            id: selectionRing
            z: -1
            width: 30
            height: 30
            radius: 15
            color: "transparent"
            border.width: 2
            border.color: palette.highlight
            opacity: 0

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }
        }
    }

    TextField {
        Layout.fillWidth: true
        visible: type === "string" || type === "integer"
        text: host.values[key] !== undefined && host.values[key] !== null
            ? String(host.values[key]) : ""
        onEditingFinished: {
            if (type === "integer") {
                var number = parseInt(text, 10)
                if (!isNaN(number))
                    host.commit(key, number)
            } else {
                host.commit(key, text)
            }
        }
    }

    // 应用快捷启动器的启动器单元列表（applauncher 专用，先例同 timezoneList）：
    // 每行 = 一个启动器单元（应用图标 + 显示名），点行开三级应用列表替换，
    // ✕ 移除；行首"≡"手柄按住上下拖放可排序（松手一次性落盘）；
    // 行对象按应用持久化（不随重排重建），重排时各行以 y 动画平滑滑向新位置；
    // 总数上限继承当前卡片尺寸容量（host.launcherCapacity()），末尾 Add 追加
    ColumnLayout {
        id: launcherPanel
        Layout.fillWidth: true
        visible: type === "launcherList"
        spacing: 8

        // 行几何常量：拖放坐标换算依赖（行高 + 行距 = 步长）
        readonly property int launcherRowHeight: 30
        readonly property int launcherRowSpacing: 6
        readonly property int launcherRowStep: launcherPanel.launcherRowHeight
            + launcherPanel.launcherRowSpacing

        // 拖放排序状态：拖动期间不改顺序，仅高亮目标行并半透明被拖行；
        // 松手后 commit 一次 → orderList 变化 → syncRows 平滑滑动重排
        property int dragFrom: -1
        property int dragTo: -1
        property bool draggingRow: false
        // 虚影跟随指针（rowsWrap 坐标系，已钳制在行列表范围内）
        property real ghostY: 0
        // 快照就绪后才允许淡化原行（避免把半透明行拍进虚影）
        property bool dragVisualReady: false

        // 顺序快照（随配置落盘整包替换而刷新）
        readonly property var orderList: host.launcherList(key)
        // 管理区只展示当前卡片容量内的单元（多余条目保留在配置里"收编"隐藏，
        // 放大卡片后自动恢复），行数/计数/Add 全部以容量为准。
        // 引用 host.launcherEditSession 让本绑定在设置面板每次打开/重建时重新求值
        //（容量来自 C++ 函数调用，普通绑定不会跟踪尺寸变化）
        readonly property int hostSession: host.launcherEditSession
        // UI 统一容量源：函数式调用自身不会被 QML 跟踪，绑定显式引用
        // hostSession（设置面板每次打开/重建 +1），保证改尺寸后重开立即刷新；
        // 所有计数/切片/Add 使能都引用本属性
        readonly property int launcherCap: host.launcherCapacity()
            + 0 * launcherPanel.hostSession
        readonly property var visibleList: launcherPanel.orderList.slice(
            0, launcherPanel.launcherCap)
        // 持久化行对象表：key = 应用 id，行内容自持，重排只改目标位置
        property var rowItems: ({})
        readonly property int launcherCount: launcherPanel.visibleList.length
        readonly property int launcherHiddenCount: Math.max(0,
            launcherPanel.orderList.length - launcherPanel.launcherCount)

        function orderIndexOf(id) {
            var o = launcherPanel.orderList
            for (var i = 0; i < o.length; ++i) {
                if (String(o[i]) === id)
                    return i
            }
            return -1
        }

        // 同步行集合：移除被删行（含复位默认/容量变化/会话切换），补充新行，
        // 既有行仅更新目标位置 → y 的 Behavior 让整列平滑滑移。
        // 关键：所有移除都先 detach（parent=null）再 destroy——QML 的 destroy()
        // 是事件循环末延迟执行，若拖到重建后，同一应用 id 会出现两张重叠的行；
        // 同时对 rowsWrap 内遗留的孤儿/重复行做自愈清理。
        function destroyRow(obj) {
            if (!obj)
                return
            obj.parent = null
            obj.visible = false
            obj.destroy()
        }

        function syncRows() {
            if (!rowsWrap || !launcherRowComponent)
                return
            var order = launcherPanel.orderList

            // 自愈：rowsWrap 下所有行可视对象（appId 为字符串者）先按出现顺序
            // 归拢进 rowItems，重复的只保留第一个并摘除其余
            var seen = {}
            var children = rowsWrap.children
            var stray = []
            for (var c = 0; c < children.length; ++c) {
                var child = children[c]
                if (!child || typeof child.appId !== "string")
                    continue
                var kid = String(child.appId)
                if (seen[kid]) {
                    stray.push(child)
                } else {
                    seen[kid] = child
                }
            }
            for (var sIdx = 0; sIdx < stray.length; ++sIdx)
                launcherPanel.destroyRow(stray[sIdx])
            launcherPanel.rowItems = seen

            // 收编/删除：不在容量内可视列表中的行摘除销毁
            var stale = []
            for (var id in launcherPanel.rowItems) {
                var pos = launcherPanel.orderIndexOf(id)
                if (pos < 0 || pos >= launcherPanel.launcherCount)
                    stale.push(id)
            }
            for (var k = 0; k < stale.length; ++k) {
                launcherPanel.destroyRow(launcherPanel.rowItems[stale[k]])
                delete launcherPanel.rowItems[stale[k]]
            }

            // 补充缺失行并统一指派目标位置（既有行靠 y Behavior 滑移）
            for (var i = 0; i < launcherPanel.launcherCount; ++i) {
                var key = String(order[i])
                var item = launcherPanel.rowItems[key]
                if (!item) {
                    // 创建即落在目标位，避免首开时的入场滑动
                    item = launcherRowComponent.createObject(rowsWrap, {
                        "appId": key, "orderIndex": i })
                    launcherPanel.rowItems[key] = item
                } else {
                    item.orderIndex = i
                }
            }
        }

        // 会话级全量重建：清空 rowsWrap 全部行并按其当前顺序重新创建。
        // 用于重开面板/尺寸重建（hostSession 变化）——任何上一会话的残留
        // （重复行、孤儿行、旧几何）都被彻底清除，从机制上杜绝重叠。
        function rebuildRows() {
            if (!rowsWrap || !launcherRowComponent)
                return
            var all = []
            for (var id in launcherPanel.rowItems)
                all.push(launcherPanel.rowItems[id])
            launcherPanel.rowItems = {}
            for (var k = 0; k < all.length; ++k)
                launcherPanel.destroyRow(all[k])
            // rowsWrap 下未登记的行可视对象（历史残留）一并摘除
            var children = rowsWrap.children
            for (var c = 0; c < children.length; ++c) {
                var child = children[c]
                if (child && typeof child.appId === "string")
                    launcherPanel.destroyRow(child)
            }
            var order = launcherPanel.orderList
            var count = launcherPanel.launcherCount
            for (var i = 0; i < count && i < order.length; ++i) {
                var key = String(order[i])
                if (launcherPanel.rowItems[key])
                    continue
                var item = launcherRowComponent.createObject(rowsWrap, {
                    "appId": key, "orderIndex": i })
                launcherPanel.rowItems[key] = item
            }
        }

        // 会话切换（重开面板/尺寸重建）时：复位拖拽残留（虚影/滚动锁）并全量重建行集
        function resetDragSilent() {
            if (!launcherPanel.draggingRow)
                return
            launcherPanel.draggingRow = false
            launcherPanel.dragVisualReady = false
            ghostTimeout.stop()
            ghostWrap.visible = false
            ghostImage.source = ""
            launcherPanel.dragFrom = -1
            launcherPanel.dragTo = -1
            host.endRowDrag()
        }
        onHostSessionChanged: {
            launcherPanel.resetDragSilent()
            launcherPanel.rebuildRows()
        }

        function rowFromY(y) {
            var r = Math.floor(y / launcherPanel.launcherRowStep)
            return Math.max(0, Math.min(launcherPanel.launcherCount - 1, r))
        }

        // 行组件随设置行销毁时兜底解锁滚动
        Component.onDestruction: {
            if (launcherPanel.draggingRow)
                host.endRowDrag()
        }

        // 快照失败兜底：一段时间后仍淡化原行给出拖拽反馈
        Timer {
            id: ghostTimeout
            interval: 350
            onTriggered: launcherPanel.dragVisualReady = true
        }

        function beginRowDrag(from, sourceItem) {
            launcherPanel.dragFrom = from
            launcherPanel.dragTo = from
            launcherPanel.draggingRow = true
            launcherPanel.dragVisualReady = false
            launcherPanel.ghostY = from * launcherPanel.launcherRowStep
            ghostWrap.visible = false
            ghostImage.source = ""
            ghostTimeout.start()
            host.beginRowDrag()
            // 拍下行快照作为拖拽虚影（与主面板拖卡预览同技术）
            if (sourceItem && typeof sourceItem.grabToImage === "function") {
                sourceItem.grabToImage(function(result) {
                    launcherPanel.dragVisualReady = true
                    if (launcherPanel.draggingRow && result
                        && result.url.toString().length > 0) {
                        ghostImage.source = result.url
                        ghostWrap.visible = true
                    }
                }, Qt.size(sourceItem.width, sourceItem.height))
            }
        }

        function updateRowDrag(y) {
            launcherPanel.dragTo = launcherPanel.rowFromY(y)
            var half = launcherPanel.launcherRowHeight / 2
            launcherPanel.ghostY = Math.max(0, Math.min(
                Math.max(0, rowsWrap.height - launcherPanel.launcherRowHeight),
                y - half))
        }

        function endRowDrag() {
            if (!launcherPanel.draggingRow)
                return
            launcherPanel.draggingRow = false
            launcherPanel.dragVisualReady = false
            ghostTimeout.stop()
            ghostWrap.visible = false
            ghostImage.source = ""
            var from = launcherPanel.dragFrom
            var to = launcherPanel.dragTo
            launcherPanel.dragFrom = -1
            launcherPanel.dragTo = -1
            host.endRowDrag()
            if (from !== to)
                host.reorderLaunchers(key, from, to)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: modelData.label ? modelData.label : modelData.key
                font: DTK.fontManager.t6
                color: palette.windowText
            }

            Text {
                text: launcherPanel.launcherCount + "/"
                    + launcherPanel.launcherCap
                font: DTK.fontManager.t7
                color: palette.windowText
                opacity: 0.6
            }
        }

        // 收编提示：配置里还有超出当前容量、放大卡片后恢复的单元
        Text {
            Layout.fillWidth: true
            visible: launcherPanel.launcherHiddenCount > 0
            text: qsTr("Hidden: %1 more (restored when the card is enlarged)")
                .arg(launcherPanel.launcherHiddenCount)
            font: DTK.fontManager.t7
            color: palette.windowText
            opacity: 0.6
            elide: Text.ElideRight
        }

        // 行列表容器：行对象按 orderIndex 绝对定位（y Behavior 滑动），
        // 高亮层绝对定位叠加；容器高度 = 行数 * 步长 - 末行距
        Item {
            id: rowsWrap
            Layout.fillWidth: true
            height: Math.max(0, launcherPanel.launcherCount
                * launcherPanel.launcherRowStep - launcherPanel.launcherRowSpacing)
            clip: false

            // 拖放目标行高亮（非行成员，画在行列表上层）
            Rectangle {
                visible: launcherPanel.draggingRow
                width: parent.width
                height: launcherPanel.launcherRowHeight
                y: launcherPanel.dragTo * launcherPanel.launcherRowStep
                radius: DTK.platformTheme.windowRadius
                color: Qt.rgba(palette.highlight.r, palette.highlight.g,
                               palette.highlight.b, 0.12)
                border.width: 1
                border.color: palette.highlight
            }

            // 拖拽虚影：被拖行的快照，跟随指针移动（置顶于行列表之上）
            Rectangle {
                id: ghostWrap
                visible: false
                z: 6
                width: parent.width
                height: launcherPanel.launcherRowHeight
                y: launcherPanel.ghostY
                radius: DTK.platformTheme.windowRadius
                color: "transparent"
                layer.enabled: true
                layer.samples: 4
                layer.smooth: true
                opacity: 1.0
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }

                Image {
                    id: ghostImage
                    anchors.fill: parent
                    source: ""
                    fillMode: Image.Stretch
                    smooth: true
                }

                Rectangle {
                    anchors.fill: parent
                    radius: DTK.platformTheme.windowRadius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(palette.highlight.r, palette.highlight.g,
                                          palette.highlight.b, 0.35)
                }
            }
        }

        // 单行可视组件（持久化实例，按 appId 复用）
        Component {
            id: launcherRowComponent

            Item {
                id: row
                property string appId: ""
                property int orderIndex: 0

                width: rowsWrap.width
                height: launcherPanel.launcherRowHeight
                y: row.orderIndex * launcherPanel.launcherRowStep

                // 平滑滑动到新位置
                Behavior on y {
                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }
                opacity: (launcherPanel.draggingRow
                          && launcherPanel.dragVisualReady
                          && launcherPanel.orderIndexOf(row.appId)
                              === launcherPanel.dragFrom) ? 0.45 : 1.0
                Behavior on opacity {
                    NumberAnimation { duration: 90 }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 4

                    // 拖动手柄（仅多行时出现）
                    Item {
                        Layout.preferredWidth: launcherPanel.launcherCount > 1 ? 20 : 0
                        Layout.preferredHeight: launcherPanel.launcherRowHeight
                        visible: launcherPanel.launcherCount > 1

                        Text {
                            anchors.centerIn: parent
                            text: "≡"
                            font.pixelSize: 14
                            color: palette.windowText
                            opacity: (dragHandle.containsMouse
                                      || launcherPanel.draggingRow) ? 0.8 : 0.4
                        }

                        MouseArea {
                            id: dragHandle
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeVerCursor

                            onPressed: function(mouse) {
                                var idx = launcherPanel.orderIndexOf(row.appId)
                                if (idx < 0)
                                    return
                                var p = dragHandle.mapToItem(rowsWrap, mouse.x, mouse.y)
                                launcherPanel.beginRowDrag(idx, row)
                            }
                            onPositionChanged: function(mouse) {
                                if (!launcherPanel.draggingRow)
                                    return
                                var p = dragHandle.mapToItem(rowsWrap, mouse.x, mouse.y)
                                launcherPanel.updateRowDrag(p.y)
                            }
                            onReleased: launcherPanel.endRowDrag()
                            onCanceled: launcherPanel.endRowDrag()
                        }
                    }

                    // 图标 + 应用名：点行开三级"选择程序"面板替换该单元
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: launcherPanel.launcherRowHeight

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 6
                                color: "transparent"

                                Image {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    sourceSize.width: 44
                                    sourceSize.height: 44
                                    source: DesktopApps.iconSource(
                                        DesktopApps.iconNameOf(row.appId), 44)
                                    smooth: true
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    var n = DesktopApps.nameOf(row.appId)
                                    return n.length > 0 ? n : row.appId
                                }
                                font: DTK.fontManager.t6
                                color: palette.windowText
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var idx = launcherPanel.orderIndexOf(row.appId)
                                if (idx >= 0)
                                    host.openLauncherPicker(key, idx)
                            }
                        }
                    }

                    Button {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 26
                        text: "✕"
                        onClicked: {
                            var idx = launcherPanel.orderIndexOf(row.appId)
                            if (idx >= 0)
                                host.removeLauncher(key, idx)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: qsTr("Restore defaults")
                onClicked: host.restoreDefaultLaunchers(key)
            }

            Item { Layout.fillWidth: true }

            Button {
                enabled: launcherPanel.launcherCount < launcherPanel.launcherCap
                text: qsTr("Add")
                onClicked: host.addLauncher(key)
            }
        }

        Component.onCompleted: launcherPanel.rebuildRows()
        onOrderListChanged: launcherPanel.syncRows()
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: type === "timezoneList"
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: modelData.label ? modelData.label : modelData.key
            font: DTK.fontManager.t6
            color: palette.windowText
        }

        Repeater {
            // 只有 timezoneList 类型的行才有数组型 dials 配置；
            // 其它行（如 refreshInterval=5000 这类数值）会把
            // 数字误当成 Repeater 的重复次数，瞬间实例化几千个
            // 委托导致 dde-shell GUI 线程卡死。统一走 host.dialList()
            // 保证模型始终是数组或空数组。
            model: host.dialList(key)
            delegate: RowLayout {
                required property int index

                Layout.fillWidth: true
                spacing: 6

                ComboBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    model: host.rowOptions(key, index)
                    textRole: "label"
                    currentIndex: host.zoneIndex(key, index)
                    onActivated: function (i) {
                        var row = host.rowOptions(key, index)
                        if (i >= 0 && i < row.length)
                            host.setDialZone(key, index, row[i].value)
                    }
                }

                Row {
                    Layout.preferredWidth: 4 * 14 + 3 * 4
                    spacing: 4

                    Repeater {
                        model: [
                            { "field": "dialBackground", "hint": "BG" },
                            { "field": "dialColor", "hint": "MK" },
                            { "field": "hourMinuteColor", "hint": "HM" },
                            { "field": "secondColor", "hint": "SS" }
                        ]
                        delegate: Rectangle {
                            required property var modelData

                            width: 14
                            height: 14
                            radius: 7
                            color: host.dialColorValue(key, index, modelData.field)
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.25)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var current = host.dialColorValue(
                                        key, index, modelData.field)
                                    host.openDialColor(key, index,
                                        modelData.field, current)
                                }
                            }
                        }
                    }
                }

                Button {
                    Layout.preferredWidth: 32
                    text: "✕"
                    onClicked: host.removeDial(key, index)
                }
            }
        }

        Button {
            text: qsTr("Add")
            onClicked: host.addDial(key)
        }
    }
}
