// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 内置小组件统一卡片：背景、圆角、标准内容边距与裁剪。
// 子内容默认放进 contentContainer，由卡片负责 10px 内边距和防溢出。
Item {
    id: root

    property int margin: 10
    property int hostCols: 0
    property int hostRows: 0
    // 宿主注入的实例配置与标识；基类先声明，主面板 Binding 才能稳定写入。
    property var widgetConfig: ({})
    property string instanceId: ""
    // 流光裁决/底色取值的配置来源：默认用宿主注入的 widgetConfig。
    // applauncher 的取色真相源是直读 instanceConfig 的 cfg，需把同一来源
    // 注入这里，否则卡底 FlowFill 与共享时钟引用计数可能落在过期配置上。
    property var flowConfig: null
    // 本卡“卡片底色”对应的配置键：常规卡为 backgroundColor（含 WidgetCard
    // 的默认背景），便签把底色重绑定到 contentBackgroundColor。
    property string backgroundSiteKey: "backgroundColor"
    // 主题色：各小组件从 widgetConfig 解析后注入；palette 设置会传递给子内容
    property color backgroundColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#1e1e1e" : "#f5f5f5"
    // 默认值必须不依赖 palette：palette 又由本卡片的这些属性反向级联，
    // 若默认值引用 palette 会形成循环绑定，且子类型重声明也无法修正基类内部读取。
    property color textColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#e8e8e8" : "#1a1a1a"
    property color highlightColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#4d8cff" : "#0081ff"
    property color highlightedTextColor: "#ffffff"
    property bool transparentBackground: false
    // 面板级"卡片透明模式"（宿主注入）：与实例自身的 transparentBackground 解耦，
    // 仅作用于本卡片的背景叠层，不影响小组件内部区域底色（日历/便签等仍由
    // transparentBackground 单独决定）。二者任一开启即用半透明叠层卡片底。
    property bool hostCardTransparent: false
    // 任一透明开关生效（实例 transparentBackground 或面板 hostCardTransparent）；
    // 小组件据此渲染配色模式改造前的无底色样式（主题自适应文字、无内部色块）。
    readonly property bool effectiveTransparent: root.transparentBackground
        || root.hostCardTransparent
    // 主题自适应文字色（与默认 textColor 取值一致，但不可被小组件覆盖——
    // 日历/便签等覆盖了 textColor 为面板专用色，透明模式需要真正的主题色）。
    readonly property color themeTextColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#e8e8e8" : "#1a1a1a"
    // 宿主注入的实例数据目录；由主面板的 Binding 写入，供持久化组件使用。
    property string dataDir: ""
    default property alias contentData: contentContainer.data

    // ── 流光时钟引用计数 ──────────────────────────────────────────────────
    // 递归扫描配置，判断是否存在任何 @flow: 值（限深，防止配置嵌套过深时递归失控）
    function configHasFlow(value, depth) {
        if (depth > 8 || value === null || value === undefined)
            return false
        if (typeof value === "string")
            return ColorUtils.isFlow(value)
        if (typeof value !== "object")
            return false
        for (var key in value)
            if (configHasFlow(value[key], depth + 1))
                return true
        return false
    }
    readonly property var flowSource: root.flowConfig ? root.flowConfig : root.widgetConfig
    readonly property bool hasFlowConfig: configHasFlow(root.flowSource, 0)
    // 整卡唯一互斥：只有底色本身是确定性的流光 owner 才铺整卡彩虹。
    // 底色键被其它部位（文字/表盘等）占用流光时回退为纯色、不显示流光层，
    // 与设置面板落盘收敛一致（渲染层只承认 owner 生效）。
    readonly property bool backgroundIsFlow: ColorUtils.flowSiteIsOwner(
        root.flowSource, "dials", root.backgroundSiteKey)
    // 私有实现细节：本卡片是否已持有共享时钟（避免重复 acquire/release）
    property bool flowAcquired: false
    // 初始值可能就是 true，故不能只在 onHasFlowConfigChanged 里同步
    function syncFlowRef() {
        if (root.hasFlowConfig && !root.flowAcquired) {
            ColorUtils.acquireFlow()
            root.flowAcquired = true
        } else if (!root.hasFlowConfig && root.flowAcquired) {
            ColorUtils.releaseFlow()
            root.flowAcquired = false
        }
    }
    onHasFlowConfigChanged: syncFlowRef()
    Component.onCompleted: syncFlowRef()
    // 卡片销毁时必须归还引用，否则计数残留会让共享时钟一直空转
    Component.onDestruction: if (root.flowAcquired) ColorUtils.releaseFlow()

    clip: true
    palette.windowText: root.textColor
    palette.highlight: root.highlightColor
    palette.highlightedText: root.highlightedTextColor

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        // 透明模式（实例开关或面板级卡片透明模式任一开启）：恢复主题色改造前的
        // 半透明叠层观感（暗色白雾/亮色黑雾），配合面板毛玻璃透出背景；
        // 全部关闭则使用不透明卡片底色。底色为流光时本条背景让位给 FlowFill，
        // 避免两层半透明色相叠加后比静态底色更不透明。
        color: (root.transparentBackground || root.hostCardTransparent)
            ? (DTK.themeType === ApplicationHelper.DarkType
                ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
            : (root.backgroundIsFlow ? "transparent" : root.backgroundColor)
    }

    // 底色为流光时的整卡横向彩虹渐变；透明模式下不显示，与底色逻辑保持一致。
    // 原色取自 backgroundSiteKey 指向的配置键（便签为 contentBackgroundColor）
    FlowFill {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        baseColor: ColorUtils.flowBase(
            root.flowSource ? root.flowSource[root.backgroundSiteKey] : "", "#4d8cff")
        visible: root.backgroundIsFlow
                 && !root.transparentBackground && !root.hostCardTransparent
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: root.margin
        clip: true
    }
}
