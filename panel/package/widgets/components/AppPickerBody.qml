// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0

// "选择应用"面板内容体（AppPickerDialog 二级 / AppPickerLevel3 三级两个窗口壳共用）：
// 搜索框 + 全部可见应用（图标 + 应用名，来自宿主 DesktopApps 代理，与 dde-shell
// 同源）+ 点选（高亮 + ✓）+ 底部 取消/确认。
//
// 选择语义由窗口壳在 openTarget() 时注入：
//  - 替换某槽位（editIndex >= 0）：单选，点其它行即换选；
//  - 追加空位（editIndex == -1）：可多选，上限 multiMax = 当前卡片剩余空位；
//    已占用程序（excludeIds）不可再选。
// 结果经 appPicked(desktopIdList) 上报；无任何窗口操作（窗口层负责开关与定位）。
Item {
    id: body

    // 宿主编辑目标（回写时用）：instanceId + 槽位（-1 = 追加）
    property string instanceId: ""
    property int editIndex: -1
    // 多选上限（追加模式 = 卡片剩余空位）；替换模式固定 1
    property int multiMax: 1
    // 当前已选中的程序 id（顺序即提交顺序）
    property var selectedIds: []
    // 追加模式下不可再选的程序（卡片上已占用的 id）
    property var excludeIds: []

    signal appPicked(var desktopIdList)
    signal canceled()

    // 宿主程序库（DesktopApps 单例）随应用增删刷新；过滤不破坏原模型。
    // 过滤直接读 DesktopApps.entries（filteredApps 内部读取），不再单独声明副本。
    property string filterText: ""
    property var shownApps: body.filteredApps()

    function filteredApps() {
        var result = []
        var f = body.filterText.trim().toLowerCase()
        var source = DesktopApps.entries
        for (var i = 0; i < source.length; ++i) {
            var item = source[i]
            if (f.length === 0
                || String(item.name).toLowerCase().indexOf(f) >= 0
                || String(item.id).toLowerCase().indexOf(f) >= 0) {
                result.push(item)
            }
        }
        return result
    }

    function isSelected(id) {
        return body.selectedIds.indexOf(id) >= 0
    }

    function isExcluded(id) {
        return body.excludeIds.indexOf(id) >= 0
    }

    // 由窗口壳在打开前调用：注入编辑目标、多选上限与已占用列表并复位
    function openTarget(instance, index, currentIds, maxSelect, exclude) {
        body.instanceId = instance
        body.editIndex = index
        body.multiMax = maxSelect > 0 ? maxSelect : 1
        body.excludeIds = Array.isArray(exclude) ? exclude : []
        var picked = Array.isArray(currentIds) ? currentIds : []
        body.selectedIds = picked.slice()
        body.filterText = ""
    }

    function toggleApp(id) {
        var pos = body.selectedIds.indexOf(id)
        if (pos >= 0) {
            var removed = body.selectedIds.slice()
            removed.splice(pos, 1)
            body.selectedIds = removed
            return
        }
        // 替换槽位模式：单选即换选
        if (body.editIndex >= 0) {
            body.selectedIds = [id]
            return
        }
        // 追加模式：不可选已占用项；达到上限后忽略新选择
        if (body.isExcluded(id))
            return
        if (body.selectedIds.length >= body.multiMax)
            return
        var next = body.selectedIds.slice()
        next.push(id)
        body.selectedIds = next
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // 标题行：右上角不再放 ✕ 关闭钮（与底部"取消"重复），关闭请用取消
        Text {
            Layout.fillWidth: true
            text: qsTr("Choose app")
            font: DTK.fontManager.t6
            color: palette.windowText
            elide: Text.ElideRight
        }

        TextField {
            id: filterField
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            placeholderText: qsTr("Search apps")
            onTextChanged: body.filterText = text
        }

        ListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: body.shownApps
            currentIndex: -1
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                anchors.right: parent.right
            }

            // 系统圆角遮罩：滚动内容按弹窗圆角裁剪
            layer.enabled: true
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: appList.width
                    height: appList.height
                    radius: DTK.platformTheme.windowRadius
                }
            }

            delegate: Item {
                required property var modelData
                required property int index

                readonly property string appId: String(modelData.id)
                readonly property string appName: String(modelData.name)
                readonly property bool sel: body.isSelected(appId)
                readonly property bool excluded: body.isExcluded(appId)
                readonly property bool full: body.selectedIds.length >= body.multiMax

                width: appList.width
                height: 44

                Rectangle {
                    anchors.fill: parent
                    radius: DTK.platformTheme.windowRadius
                    color: appRowMouse.containsMouse && !excluded
                        ? (DTK.themeType === ApplicationHelper.DarkType
                            ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                        : "transparent"
                }

                // 选中高亮（复用 DTK 高亮色）
                Rectangle {
                    anchors.fill: parent
                    radius: DTK.platformTheme.windowRadius
                    visible: sel
                    color: Qt.rgba(palette.highlight.r, palette.highlight.g,
                                   palette.highlight.b, 0.16)
                    border.width: 1
                    border.color: palette.highlight
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Image {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        sourceSize.width: 28
                        sourceSize.height: 28
                        source: DesktopApps.iconSource(
                            String(modelData.icon).length > 0
                                ? modelData.icon : modelData.id, 56)
                        smooth: true
                        opacity: excluded ? 0.45 : 1.0
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: appName
                        font: DTK.fontManager.t6
                        elide: Text.ElideRight
                        color: palette.windowText
                        opacity: excluded ? 0.45 : 1.0
                    }

                    Text {
                        visible: sel
                        Layout.alignment: Qt.AlignVCenter
                        text: "✓"
                        color: palette.highlight
                        font.pixelSize: 14
                    }

                    // 追加模式：已占用不可再选、满额后未选行给一个弱化提示
                    Text {
                        visible: !sel && !excluded && full
                        Layout.alignment: Qt.AlignVCenter
                        text: "–"
                        color: palette.windowText
                        opacity: 0.35
                        font.pixelSize: 14
                    }
                }

                MouseArea {
                    id: appRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: body.toggleApp(appId)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: appList.count === 0
                text: qsTr("No matching apps")
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.6
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: body.editIndex < 0
                text: qsTr("Selected: %1/%2").arg(body.selectedIds.length)
                    .arg(body.multiMax)
                font: DTK.fontManager.t7
                color: palette.windowText
                opacity: 0.6
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: body.canceled()
            }

            Button {
                text: qsTr("Confirm")
                enabled: body.selectedIds.length > 0
                onClicked: {
                    body.appPicked(body.selectedIds.slice())
                }
            }
        }
    }
}
