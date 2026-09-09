// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// "选择应用"面板 —— 三级形态（从小组件二级设置面板唤起，覆盖在设置面板之上，
// 与取色器"色卡"同级弹中弹，二者以 avoidOffsetX 互相避让）。
// 弹窗壳结构与 ColorPickerDialog 一致：自建 PanelPopupWindow + transientParent
// 锚定宿主设置弹窗，水平浮在其左侧、垂直居中。内容体见 AppPickerBody。
PanelPopup {
    id: root

    // 父弹窗窗口（transientParent）与父弹窗高度（popupY 垂直居中基准），由宿主注入
    property var hostPopupWindow: null
    property int hostHeight: 480
    // 避让偏移：同级的"色卡"取色面板若正打开，向左再挪出它的宽度，避免叠窗
    property real avoidOffsetX: 0

    // 宿主编辑目标（回写时用）：instanceId + 槽位（-1 = 追加空位）
    property string instanceId: ""
    property int editIndex: -1
    property var selectedIds: []
    // 追加模式多选上限（当前卡片剩余空位）；替换模式为 1
    property int multiMax: 1
    // 追加模式下已占用的程序 id（不再可选）
    property var excludeIds: []

    signal appPicked(var desktopIdList)
    signal canceled()

    width: 380
    height: 540
    popupWindow: pickerWindow
    popupX: -root.width - 8 - root.avoidOffsetX
    popupY: Math.max(0, (root.hostHeight - root.height) / 2)
    windowTitle: "dde-shell/widgettoolbar-app-picker-level3"

    property PanelPopupWindow pickerWindow: PanelPopupWindow {
        id: pickerWindow
        transientParent: root.hostPopupWindow
    }

    function openFor(instance, index, currentIds, maxSelect, excludeIds) {
        root.instanceId = instance
        root.editIndex = index
        root.selectedIds = Array.isArray(currentIds) ? currentIds : []
        root.multiMax = maxSelect > 0 ? maxSelect : 1
        root.excludeIds = Array.isArray(excludeIds) ? excludeIds : []
        body.openTarget(instance, index, root.selectedIds,
                        root.multiMax, root.excludeIds)
        root.open()
    }

    onPopupVisibleChanged: {
        if (popupVisible)
            focus = true
    }

    AppPickerBody {
        id: body
        anchors.fill: parent

        onAppPicked: function(desktopIdList) {
            root.appPicked(desktopIdList)
            root.close()
        }
        onCanceled: {
            root.canceled()
            root.close()
        }
    }
}
