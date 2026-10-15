// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Window

// 省略文字悬停全文气泡（被动观察者）：
//
// 用法：作为任何设置了 elide 的 Text 的子项声明 `ElideTip { anchors.fill:
// parent }`。本组件自身透明、不绘制任何内容，也不参与父级布局（Text 不按
// 子项布局），对文字外观零影响。
//
// 行为：仅当 enabled 且 target 可见、target.truncated 为真（文字确实被
// “…”截断）、target.text 非空、鼠标悬停其上时，延迟约 400ms 在指针右下
// 附近浮出 ToolTip 显示全文；移开立即消失。未截断时绝不提示。
//
// 事件语义：悬停用 HoverHandler 被动跟踪——它不建立任何鼠标抓取、也不消费
// 按键事件，被观察区域上的点击/长按/右键仍原样到达下层 MouseArea。
// 注意 Qt 6 的悬停投递只会沿“命中点最上层悬停叶子→祖先链”传播：若目标
// Text 被同级更晚声明（绘制在上层）且 hoverEnabled:true 的 MouseArea
// 盖住，Text 内部的 HoverHandler 收不到悬停。正解是就地改造那个
// MouseArea：去掉 hoverEnabled，把其悬停视觉（containsMouse 底色/手型
// 光标）迁移到挂在同一行根上的 HoverHandler（多被动处理器可沿祖先链
// 共存），ElideTip 始终留在 Text 内部。切勿把 ElideTip 上提为覆盖
// 兄弟：上提的 HoverHandler 命中后同样会阻断兄弟子树的悬停投递。
Item {
    id: root

    // 观察目标；缺省即父项（常规作为 Text 子项的用法）。
    // 如需观察非父项的 Text，可显式绑定，但调用方需自行保证悬停可达。
    property var target: parent

    // 总开关：同时透传给 HoverHandler。外部可绑定条件临时关闭，
    // 例如面板卡片拖拽中禁用（enabled: !root.panelDragging）。
    enabled: true

    // 是否满足提示前提：开关开、目标存在且可见、确已截断、文本非空。
    readonly property bool canTip: root.enabled
        && root.target !== null
        && root.target.visible === true
        && root.target.truncated === true
        && String(root.target.text).length > 0

    // 气泡显式状态：延迟满足后置真；移开或前提失效立即清掉。
    property bool showBubble: false

    // 前提在显示期间失效（如面板变宽使文字不再截断）时立即收泡。
    onCanTipChanged: if (!root.canTip)
        root.showBubble = false

    // 被动悬停跟踪；禁用后不跟踪任何悬停。
    HoverHandler {
        id: hover
        enabled: root.enabled
        onHoveredChanged: if (!hovered)
            root.showBubble = false
    }

    // 约 400ms 延迟：悬停持续且前提成立时才计时；移开/失条件时
    // running 绑定自动转假，计时器复位。
    Timer {
        id: delayTimer
        interval: 400
        repeat: false
        running: root.canTip && hover.hovered
        onTriggered: root.showBubble = true
    }

    // 指针在窗口内容坐标系中的位置（mapToItem(null) 的目标即窗口
    // contentItem）；未悬停时为 null。
    function pointerPoint() {
        if (!hover.hovered)
            return null
        return root.mapToItem(null, hover.point.position.x,
                             hover.point.position.y)
    }

    // 独立 ToolTip（非 ToolTip.attached 附加属性用法）：手动控制
    // x/y 与 visible。parent 显式取窗口 contentItem，使气泡坐标与
    // mapToItem(null) 换算出的窗口坐标处于同一坐标系。
    ToolTip {
        id: bubble
        parent: root.Window.window ? root.Window.window.contentItem : root
        // 显示/隐藏完全由上面的悬停状态驱动，不使用 ToolTip 自带超时。
        timeout: -1
        padding: 8
        visible: root.showBubble && root.canTip && hover.hovered
        // 气泡内容即目标 Text 的全文（原文透显，不做翻译）。
        text: root.target !== null ? root.target.text : ""

        // 指针右下偏移 16px；再钳制在窗口可视区内不越界。
        // 拿不到窗口时退化为仅保证非负的保守钳制。
        x: {
            var p = root.pointerPoint()
            if (!p)
                return 0
            var cx = p.x + 16
            var win = root.Window.window
            if (win) {
                var maxX = win.contentItem.width - bubble.implicitWidth - 4
                return Math.max(4, Math.min(cx, maxX))
            }
            return Math.max(4, cx)
        }
        y: {
            var p = root.pointerPoint()
            if (!p)
                return 0
            var cy = p.y + 16
            var win = root.Window.window
            if (win) {
                var maxY = win.contentItem.height - bubble.implicitHeight - 4
                return Math.max(4, Math.min(cy, maxY))
            }
            return Math.max(4, cy)
        }
    }
}
