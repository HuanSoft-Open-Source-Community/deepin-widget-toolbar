// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../components" as Components

// 世界时间指针模式的表盘网格视图（从 worldtime 小组件拆分）：
// 随 hostCols/hostRows 网格排布 AnalogClock，属性由调用方注入。
Grid {
    id: root

    property var zoneInfos: []
    property int hostCols: 2
    property int hostRows: 2
    property bool showLabels: true
    property bool highlightLocal: false
    property real localOffset: 0
    property color highlightColor: palette.highlight
    property color textColor: palette.windowText
    // 透明模式（由调用方传入 WidgetCard 的 effectiveTransparent/themeTextColor）
    property bool effectiveTransparent: false
    property color themeTextColor: palette.windowText
    property bool preloadTime: true
    property bool active: false
    // 整卡互斥与空间采样参考（由 main.qml 注入）：cardConfig=实例配置；
    // cardWidth=卡片宽；cardOffsetX=内容区相对卡片左缘的 x 偏移
    property var cardConfig: null
    property real cardWidth: 0
    property real cardOffsetX: 0
    // 单表盘未配置子色时的兜底（由调用方传入 root 的已解析颜色）
    property color fallbackDialBackground: "#ffffff"
    property color fallbackDialColor: "#000000"
    property color fallbackHourMinute: "#000000"
    property color fallbackSecond: "#ff4d4f"

    visible: zoneInfos.length > 0
    anchors.fill: parent
    columns: root.hostCols
    rows: root.hostRows
    spacing: 2

    Repeater {
        model: root.zoneInfos.slice(0, root.hostCols * root.hostRows)
        delegate: Item {
            id: dialCell
            required property var modelData
            required property int index

            width: Math.max(1,
                (root.width - (root.hostCols - 1) * root.spacing) / root.hostCols)
            height: Math.max(1,
                (root.height - (root.hostRows - 1) * root.spacing) / root.hostRows)

            // 表盘中心相对卡片左缘的 x（DialGrid 由卡片 margin 内边距包裹，
            // 委托 x 加偏移换算到卡片坐标，与 FlowFill/文字彩虹同一口径）
            readonly property real cardCenterX: root.cardOffsetX
                + dialCell.x + dialCell.width / 2

            // ── 子色位取色：per-dial 值优先，缺省回退全局配置键 ──────────────
            // 4 个子色位既可能写在 dials.<i>.<field>，也可能只配置了全局键
            // （dialBackgroundColor / dialColor / hourMinuteHandColor /
            // secondHandColor）。两种情况都必须把“该 site 是否整卡唯一流光
            // owner + 本表盘中心 x”交给 ColorUtils 裁决，全局键为流光时才能
            // 按每块表盘铺开彩虹，而不是共用卡片中心解析出的单色。
            function fieldDefault(field) {
                if (field === "dialBackground")
                    return "#ffffff"
                if (field === "dialColor" || field === "hourMinuteColor")
                    return "#000000"
                return "#ff4d4f"
            }
            function globalKey(field) {
                if (field === "dialBackground")
                    return "dialBackgroundColor"
                if (field === "dialColor")
                    return "dialColor"
                if (field === "hourMinuteColor")
                    return "hourMinuteHandColor"
                return "secondHandColor"
            }
            function fallbackColor(field) {
                if (field === "dialBackground")
                    return root.fallbackDialBackground
                if (field === "dialColor")
                    return root.fallbackDialColor
                if (field === "hourMinuteColor")
                    return root.fallbackHourMinute
                return root.fallbackSecond
            }
            // 未配置返回 undefined；空串同样视为未配置（与 dialslogic 的
            // resolveColor 回退语义一致）
            function ownValue(field) {
                var value = dialCell.modelData ? dialCell.modelData[field] : undefined
                if (value === undefined || value === null || value === "")
                    return undefined
                return value
            }
            function dialSite(field) {
                return ownValue(field) !== undefined
                    ? Components.ColorUtils.flowSiteKeyOf("dials", dialCell.index, field)
                    : globalKey(field)
            }
            function dialValue(field) {
                var own = ownValue(field)
                if (own !== undefined)
                    return own
                return root.cardConfig ? root.cardConfig[globalKey(field)] : undefined
            }
            // 有 per-dial 值时 fallback 保持原有 root.fallback*（非法值旧行为）；
            // 无 per-dial 值时改用该字段静态缺省，让全局 site 自己参与 owner 裁决
            function dialSiteColor(field, canvas) {
                var own = ownValue(field)
                var fallback = own !== undefined ? fallbackColor(field)
                                                 : fieldDefault(field)
                if (canvas)
                    return Components.ColorUtils.canvasSiteColor(
                        root.cardConfig, "dials", dialSite(field),
                        dialValue(field), fallback,
                        dialCell.cardCenterX, root.cardWidth)
                return Components.ColorUtils.resolveSiteColor(
                    root.cardConfig, "dials", dialSite(field),
                    dialValue(field), fallback,
                    dialCell.cardCenterX, root.cardWidth)
            }
            // 面/刻度进入 Canvas 逐图元采样所需的 owner/base；全局键为 owner
            // 时同样生效，base 取全局值的内嵌原色
            function dialFlowMeta(field) {
                var value = dialValue(field)
                return {
                    "owner": Components.ColorUtils.flowSiteIsOwner(
                        root.cardConfig, "dials", dialSite(field))
                        && Components.ColorUtils.isFlow(value),
                    "base": Components.ColorUtils.flowBase(value, fieldDefault(field))
                }
            }

            Components.AnalogClock {
                anchors.fill: parent
                utcOffset: modelData.offset
                label: modelData.name
                showLabels: root.showLabels
                highlighted: root.highlightLocal
                    && Math.abs(modelData.offset - root.localOffset) < 0.001
                accentColor: root.highlightColor
                // 4 子色位以 dials.<i>.<field> 或全局键路径参与整卡互斥：
                // owner 按本表盘中心 x 空间采样彩虹，非 owner 的 @flow: 自动
                // 回退静态兜底色；面/刻度走 Canvas 低频相位，指针走高频相位
                faceBackgroundColor: dialCell.dialSiteColor("dialBackground", true)
                // 透明模式下不绘制表盘底色（配色模式前样式）
                transparentFace: root.effectiveTransparent
                dialColor: dialCell.dialSiteColor("dialColor", true)
                // 指针为场景图矩形：调用方 owner 门控解析后注入
                hourMinuteHandColor: dialCell.dialSiteColor("hourMinuteColor", false)
                secondHandColor: dialCell.dialSiteColor("secondColor", false)
                // 表盘标签：透明模式用主题自适应文字色（默认 #ffffff 是为黑底设计的）
                textColor: root.effectiveTransparent ? root.themeTextColor : root.textColor
                preloadTime: root.preloadTime
                active: root.active
                // 流光逐图元采样参考：卡片宽与本表盘中心相对卡片 x；
                // 面/刻度 site 为 owner 时在 Canvas 内按各刻度自身 x 描彩虹
                flowWidthRef: root.cardWidth
                flowCenterX: dialCell.cardCenterX
                flowMeta: ({
                    "face": dialCell.dialFlowMeta("dialBackground"),
                    "dial": dialCell.dialFlowMeta("dialColor")
                })
            }
        }
    }
}
