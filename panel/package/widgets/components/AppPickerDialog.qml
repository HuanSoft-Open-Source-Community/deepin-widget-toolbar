// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// "选择应用"面板 —— 二级形态（仅由卡片内"+"直接唤起；此时没有二级设置面板，
// 相对面板本体它就是第二级）。弹窗形态与 SettingsDialog/AddWidgetPopup 完全一致：
// PanelPopup 默认辅助窗口，不覆盖 popupWindow（自建窗口 + transientParent 只用于
// 弹中弹的"三级"形态，见 AppPickerLevel3）。内容体见 AppPickerBody。
PanelPopup {
    id: root

    // 弹在侧栏面板左侧；popupY 打开前由宿主 positionPopup 重定位
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-app-picker"

    width: 380
    height: 540

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
