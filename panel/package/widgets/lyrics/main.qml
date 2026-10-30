// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：端闱乐部歌词（默认 4×2，占满一行）
// 支持按实例配置字体族与基础颜色；数据仍由宿主 Lyrics 代理提供。
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    property string lyricFontFamily: widgetConfig && widgetConfig.lyricsFont
        ? widgetConfig.lyricsFont : DTK.fontManager.t4.family
    property string lyricColor: widgetConfig && widgetConfig.lyricsColor
        ? widgetConfig.lyricsColor : "auto"
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 取色统一走 ColorUtils Site 入口：整卡唯一 owner 互斥兜底 + 横向空间渐变采样
    //（本卡元素横贯卡面，x 传元素中心；左右歌词槽的采样 x 见槽位绑定）
    backgroundColor: Components.ColorUtils.themedOpaqueSiteColor(
        widgetConfig, "dials", "backgroundColor",
        widgetConfig && widgetConfig.backgroundColor, "#ffffc0cb", "#ff4a2b31",
        root.width / 2, root.width)
    // 标题元素为 fillWidth（扣除状态点 8px + 间距 6px），中心 x = (卡宽 - 14) / 2
    property color titleTextColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "titleTextColor",
        widgetConfig && widgetConfig.titleTextColor, "#7a1f33", "#f0c8d0",
        (root.width - 14) / 2, root.width)
    property color statusTextColor: Components.ColorUtils.themedSiteColor(
        widgetConfig, "dials", "statusTextColor",
        widgetConfig && widgetConfig.statusTextColor, "#7a3b4a", "#e6b9c2",
        root.width / 2, root.width)
    // 流光值必须原样保留字符串：themedColor 对流光返回 color 对象，
    // 赋给 string 属性会把 @flow: 前缀转成静态 hex，丢掉流光语义
    property string inactiveTextColor: {
        var configured = widgetConfig && widgetConfig.inactiveTextColor
        if (Components.ColorUtils.isFlow(configured))
            return configured
        return Components.ColorUtils.themedSiteColor(
            widgetConfig, "dials", "inactiveTextColor",
            configured, "#8a4a55", "#cfa6ad", root.width / 2, root.width)
    }
    // 文字部位整卡唯一流光 owner 判定（FlowText 门控；site 用配置键，
    // 歌词色的配置键为 lyricsColor，宿主属性名为 lyricColor）
    readonly property bool lyricsColorIsFlow: Components.ColorUtils.flowSiteIsOwner(
        widgetConfig, "dials", "lyricsColor")
        && Components.ColorUtils.isFlow(widgetConfig && widgetConfig.lyricsColor)
    readonly property bool inactiveTextColorIsFlow: Components.ColorUtils.flowSiteIsOwner(
        widgetConfig, "dials", "inactiveTextColor")
        && Components.ColorUtils.isFlow(widgetConfig && widgetConfig.inactiveTextColor)
    property int contentHeight: Math.max(1, height - margin * 2)
    property int activePixelSize: Math.max(13, Math.min(42,
        Math.round(contentHeight * 0.105)))
    property int inactivePixelSize: Math.max(11, Math.min(32,
        Math.round(contentHeight * 0.078)))

    property string statusText: {
        if (!Lyrics.connected)
            return qsTr("Start Ter-Music and play a song to show lyrics")
        if (!Lyrics.hasTrack)
            return qsTr("Ter-Music is not playing")
        if (!Lyrics.hasLyrics)
            return qsTr("This track has no lyrics")
        return ""
    }

    function textColor(active) {
        // auto 模式回退色：亮色淡粉底用深色文字，暗色粉底用浅色文字，保证可读性
        var fallback = Components.ColorUtils.dark
            ? (active ? "#f0a8be" : "#d9bcc6")
            : (active ? "#b0305a" : "#5a2233")
        if (root.lyricColor !== "auto") {
            // 流光值经 Site 入口解析：owner 按歌词元素中心 x 采样（slot 元素
            // 横贯卡面，中心即卡宽一半），非 owner 流光回退缺省色
            if (Components.ColorUtils.isFlow(root.lyricColor))
                return Components.ColorUtils.resolveSiteColor(
                    root.widgetConfig, "dials", "lyricsColor",
                    root.lyricColor, fallback, root.width / 2, root.width)
            return root.lyricColor
        }
        return fallback
    }

    function inactiveColor(activeColor, x) {
        // 流光值必须单独走 Site 入口：owner 按左右 slot 的 x 采样，非 owner
        // 流光回退兜底色；它返回 color 对象，没有 length 可判断，故与静态分支分开
        if (Components.ColorUtils.isFlow(root.inactiveTextColor))
            return Components.ColorUtils.resolveSiteColor(
                root.widgetConfig, "dials", "inactiveTextColor",
                root.inactiveTextColor, activeColor, x, root.width)
        if (root.inactiveTextColor !== "auto") {
            var resolved = Components.ColorUtils.resolveSiteColor(
                root.widgetConfig, "dials", "inactiveTextColor",
                root.inactiveTextColor, "", x, root.width)
            if (resolved.length > 0)
                return resolved
        }
        return activeColor
    }

    // 标题行：标题 + 连接状态圆点
    RowLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 2
            leftMargin: 2
            rightMargin: 2
        }
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: qsTr("Ter-Music Lyrics")
            font: DTK.fontManager.t6
            color: root.titleTextColor
            elide: Text.ElideRight
            // 标题截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
        }

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: Lyrics.connected
                ? Qt.rgba(0.35, 0.78, 0.42, 1)
                : Qt.rgba(0.5, 0.5, 0.5, 0.55)
        }
    }

    ColumnLayout {
        anchors {
            top: parent.top
            topMargin: 26
            left: parent.left
            leftMargin: 2
            right: parent.right
            rightMargin: 2
            bottom: parent.bottom
            bottomMargin: 2
        }
        spacing: 8
        visible: Lyrics.connected && Lyrics.hasTrack && Lyrics.hasLyrics

        // 大号歌词槽换用 FlowText：对应文字 site 为整卡唯一流光 owner 时，
        // 在字形内部呈现「横向渐变 + 跑马」；非 owner / 静态色时与普通 Text
        // 完全同路径渲染（layer 关闭，零额外开销）
        Components.FlowText {
            id: slotA
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineAText.length > 0 ? Lyrics.lineAText : "· · ·"
            font.family: root.lyricFontFamily
            font.pixelSize: Lyrics.activeLineA
                ? root.activePixelSize : root.inactivePixelSize
            color: Lyrics.activeLineA
                ? root.textColor(true)
                : root.inactiveColor(root.textColor(false),
                    root.margin + 2 + paintedWidth / 2)
            opacity: Lyrics.activeLineA ? 1.0
                : (root.inactiveTextColor === "auto" ? 0.55 : 0.85)
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            // owner 判定随激活态切换：激活行看 lyricsColor、非激活行看 inactiveTextColor
            flowGradient: Lyrics.activeLineA
                ? root.lyricsColorIsFlow : root.inactiveTextColorIsFlow
            flowBaseColor: Lyrics.activeLineA
                ? Components.ColorUtils.flowBase(root.lyricColor, root.textColor(true))
                : Components.ColorUtils.flowBase(root.inactiveTextColor,
                    root.textColor(false))
            // 相位读取按 owner 门控：非流光路径不注册 flowPhase 依赖（性能红线）
            flowPhaseValue: flowGradient ? Components.ColorUtils.flowPhase : 0
            flowDark: Components.ColorUtils.dark
            // 段内渐变与全卡口径连续：offset=元素左缘（卡边距 10 + 行边距 2），
            // span=元素宽占卡宽比例；左/右对齐文本自然取渐变的左/右段
            flowOffset: Components.ColorUtils.spaceOffset(root.margin + 2, root.width)
            flowSpan: Components.ColorUtils.spaceOffset(width, root.width)
            // 流光色逐帧变化，补间动画只会拖慢/糊掉色相，故仅在静态色时启用
            Behavior on color {
                enabled: !Components.ColorUtils.isFlow(root.lyricColor)
                    && !Components.ColorUtils.isFlow(root.inactiveTextColor)
                ColorAnimation { duration: 200 }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            // 歌词截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
        }

        Components.FlowText {
            id: slotB
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: Lyrics.lineBText.length > 0 ? Lyrics.lineBText : "· · ·"
            font.family: root.lyricFontFamily
            font.pixelSize: Lyrics.activeLineA
                ? root.inactivePixelSize : root.activePixelSize
            color: root.inactiveColor(root.textColor(!Lyrics.activeLineA),
                root.width - root.margin - 2 - paintedWidth / 2)
            opacity: Lyrics.activeLineA
                ? (root.inactiveTextColor === "auto" ? 0.55 : 0.85) : 1.0
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            // slotB 恒为非当前句样式：owner 判定只看 inactiveTextColor
            flowGradient: root.inactiveTextColorIsFlow
            flowBaseColor: Components.ColorUtils.flowBase(
                root.inactiveTextColor, root.textColor(!Lyrics.activeLineA))
            // 相位读取按 owner 门控：非流光路径不注册 flowPhase 依赖（性能红线）
            flowPhaseValue: flowGradient ? Components.ColorUtils.flowPhase : 0
            flowDark: Components.ColorUtils.dark
            flowOffset: Components.ColorUtils.spaceOffset(root.margin + 2, root.width)
            flowSpan: Components.ColorUtils.spaceOffset(width, root.width)
            // 流光色逐帧变化，补间动画只会拖慢/糊掉色相，故仅在静态色时启用
            Behavior on color {
                enabled: !Components.ColorUtils.isFlow(root.lyricColor)
                    && !Components.ColorUtils.isFlow(root.inactiveTextColor)
                ColorAnimation { duration: 200 }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            // 歌词截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
        }
    }

    Text {
        anchors {
            top: parent.top
            topMargin: 26
            left: parent.left
            leftMargin: 2
            right: parent.right
            rightMargin: 2
            bottom: parent.bottom
            bottomMargin: 2
        }
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        visible: root.statusText.length > 0
        text: root.statusText
        font: DTK.fontManager.t6
        color: root.statusTextColor
        opacity: 0.6
        wrapMode: Text.Wrap
    }
}
