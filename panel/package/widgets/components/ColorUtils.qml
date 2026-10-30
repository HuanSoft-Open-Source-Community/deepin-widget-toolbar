// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

pragma Singleton
import QtQuick
import org.deepin.dtk 1.0
import "dialslogic.js" as DialsLogic

// 颜色安全工具：所有来自用户配置的颜色必须先经这里校验，
// 只接受 #RRGGBB / #AARRGGBB，非法值回退到调用方提供的默认色。
// 另提供"主题化默认色"：默认预设随明/暗主题切换（用户自定义色仍优先生效）。
// 流光色在上述格式前加 @flow: 前缀（如 @flow:#4d8cff），表示色相随时间循环；
// 前缀后的原色只用于关闭流光时还原、以及为流光继承 alpha，不参与色相计算。
QtObject {
    id: root

    // 当前是否为暗色主题（绑定，主题切换时自动重算）
    readonly property bool dark: DTK.themeType === ApplicationHelper.DarkType

    function isValidColor(value) {
        return typeof value === "string"
            && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)
    }

    function resolveColor(value, fallback, offset) {
        // 只有流光值才碰相位；普通静态色保持返回值原样，不引入全局状态依赖
        if (isFlow(value))
            return flowColorAt(flowBase(value, fallback), flowPhase, offset || 0, dark)
        return isValidColor(value) ? value : fallback
    }

    // 主题化默认色：用户配置值（且与浅色默认值不同）优先，否则按当前主题取默认。
    // 判定"未自定义"用"是否等于浅色默认值"：宿主 instanceConfig 会把 manifest 的
    // default 一并写入实例配置，内置组件读到的配置值恒不为空，无法区分"未设置"；
    // 代价是用户刻意选中与浅色默认完全相同的颜色时，暗色下会显示暗色变体。
    function themedColor(value, lightDefault, darkDefault, offset) {
        // 流光值同属"用户自定义"，按当前主题的默认色取基准色相
        if (isFlow(value))
            return flowColorAt(flowBase(value, dark ? darkDefault : lightDefault),
                               flowPhase, offset || 0, dark)
        if (isValidColor(value) && value !== lightDefault)
            return value
        return dark ? darkDefault : lightDefault
    }

    // 卡片底色专用：透明背景开关关闭时底色必须不透明，
    // 防止旧实例里保存的半透明色让卡片露出"白边/底色不生效"的观感。
    // 8 位色为 #AARRGGBB：RRGGBB 是第 3~8 个字符（slice(3, 9)）；
    // 取 slice(1, 7) 会把 AA+RR+GG 拼成新 RGB，导致底色错位
    //（如粉 #ffffc0cb 变黄、紫 #ff8b5cf6 变橙）。
    function opaqueColor(value, fallback, offset) {
        // 流光分支必须在 resolveColor 之前判断：后者会把流光解析成 color 对象，
        // 走不到下面的字符串切片；这里直接以 alpha=1 生成流光色。
        if (isFlow(value))
            return _flowColorAt(flowBase(value, fallback), flowPhase, offset || 0, dark, 1.0)
        var color = resolveColor(value, fallback)
        if (typeof color !== "string")
            return color
        var match = /^#([0-9a-fA-F]{8})$/.exec(color)
        if (match)
            return "#ff" + color.slice(3, 9)
        return color
    }

    // 主题化 + 不透明化（卡片底色用）
    function themedOpaqueColor(value, lightDefault, darkDefault, offset) {
        if (isFlow(value))
            return _flowColorAt(flowBase(value, dark ? darkDefault : lightDefault),
                                flowPhase, offset || 0, dark, 1.0)
        return opaqueColor(themedColor(value, lightDefault, darkDefault), darkDefault)
    }

    // ── 流光色 ────────────────────────────────────────────────────────────
    // 流光值写成 @flow:<合法颜色>。前缀后的原色只用于还原与 alpha 继承，
    // 色相始终由原色自身 + 共享相位推导，这样同一预设的多个流光元素色调一致。
    // 前缀 + 合法内嵌色才算流光：@flow:zzz / @flow:#12345 一律按非法色回退静态色，
    // 避免脏值让元素进入流光态、白占共享时钟引用
    function isFlow(value) {
        return typeof value === "string" && value.indexOf("@flow:") === 0
            && isValidColor(value.slice(6))
    }

    // 取出内嵌原色；非法时用调用方兜底色，保证下游永远拿到可解析的 6/8 位色
    function flowBase(value, fallback) {
        if (!isFlow(value))
            return fallback
        var base = value.slice(6) // "@flow:".length
        return isValidColor(base) ? base : fallback
    }

    // 写配置统一走这里，避免把非法色拼进 @flow: 前缀
    function flowValue(colorText) {
        return "@flow:" + (isValidColor(colorText) ? colorText : "#4d8cff")
    }

    // QML 没有 Qt.color()/QColor，十六进制解析只能手写。
    // 与 isValidColor 一致：8 位是 #AARRGGBB（alpha 在前），不是 #RRGGBBAA。
    // 返回 [r, g, b, a]（均归一化到 0~1），非法值返回 null。
    function _rgbaFromText(text) {
        if (typeof text !== "string")
            return null
        var match = /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.exec(text)
        if (!match)
            return null
        var hex = match[1]
        var rgb = hex.length === 8 ? hex.slice(2) : hex
        return [
            parseInt(rgb.slice(0, 2), 16) / 255,
            parseInt(rgb.slice(2, 4), 16) / 255,
            parseInt(rgb.slice(4, 6), 16) / 255,
            hex.length === 8 ? parseInt(hex.slice(0, 2), 16) / 255 : 1
        ]
    }

    // RGB→HSL 只需色相：最大/最小通道之差决定它在色相环上的位置
    function _hueFromRgb(r, g, b) {
        var max = Math.max(r, g, b)
        var min = Math.min(r, g, b)
        var delta = max - min
        if (delta === 0)
            return 0
        var hue
        if (max === r)
            hue = ((g - b) / delta) % 6
        else if (max === g)
            hue = (b - r) / delta + 2
        else
            hue = (r - g) / delta + 4
        hue /= 6
        return hue < 0 ? hue + 1 : hue
    }

    // 流光取色：纯函数，isDark 显式传入而不读全局 dark，
    // 便于 Canvas 在一帧内对多个色块用同一组参数稳定取色。
    // alphaOverride 为内部参数（undefined 表示继承原色 alpha），
    // 卡片底色等场景需要强制不透明，故不放进公开签名。
    function _flowColorAt(base, phase, offset, isDark, alphaOverride) {
        var rgba = _rgbaFromText(base) || _rgbaFromText("#4d8cff")
        var hue = _hueFromRgb(rgba[0], rgba[1], rgba[2])
            + (phase || 0) + (offset || 0)
        // 取小数部分，负相位同样能归一到 [0,1)
        hue -= Math.floor(hue)
        var alpha = alphaOverride === undefined ? rgba[3] : alphaOverride
        return Qt.hsla(hue, 0.78, isDark ? 0.62 : 0.50, alpha)
    }

    // 公开的纯函数入口：同输入必同输出，不依赖任何全局状态
    function flowColorAt(base, phase, offset, isDark) {
        return _flowColorAt(base, phase, offset, isDark)
    }

    // Canvas 重绘成本高，单独走低频相位；取值逻辑与 resolveColor 一致
    function resolveCanvasColor(value, fallback, offset) {
        if (isFlow(value))
            return flowColorAt(flowBase(value, fallback), flowCanvasPhase, offset || 0, dark)
        return isValidColor(value) ? value : fallback
    }

    function themedCanvasColor(value, lightDefault, darkDefault, offset) {
        if (isFlow(value))
            return flowColorAt(flowBase(value, dark ? darkDefault : lightDefault),
                               flowCanvasPhase, offset || 0, dark)
        if (isValidColor(value) && value !== lightDefault)
            return value
        return dark ? darkDefault : lightDefault
    }

    // ── 共享时钟 ──────────────────────────────────────────────────────────
    // 引用计数：只有页面里真的存在流光色才跑定时器，静态配色不付任何代价。
    property int flowRefCount: 0
    property bool flowSuspended: false
    readonly property bool flowActive: flowRefCount > 0 && !flowSuspended
    // 0..1 循环，60 帧约 4 秒一圈
    property real flowPhase: 0
    // Canvas 专用低频相位（约 7.5fps），避免每帧重绘整块画布
    property real flowCanvasPhase: 0
    property int flowTick: 0

    function acquireFlow() {
        flowRefCount += 1
    }

    function releaseFlow() {
        // 防御性兜底：重复释放不能把计数减成负数，否则会误判为活跃
        if (flowRefCount > 0)
            flowRefCount -= 1
    }

    // 用 property 声明而不是 QtObject 默认属性：QtObject 没有 default property，
    // 直接写子对象会报错。
    property Timer flowTimer: Timer {
        interval: 66 // 约 15fps，肉眼已足够顺滑
        repeat: true
        running: root.flowActive
        onTriggered: {
            root.flowTick += 1
            root.flowPhase = (root.flowTick % 60) / 60
            // Canvas 降到约 7.5fps：低频相位不高于 10fps，且比主相位慢半拍
            if (root.flowTick % 2 === 0)
                root.flowCanvasPhase = root.flowPhase
        }
    }

    // 中性细描边（色卡/缩略图等）：亮色叠黑、暗色叠白，避免暗色下黑框不可见
    readonly property color hairline: dark
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.25)

    // ── 空间渐变 ──────────────────────────────────────────────────────────
    // 元素相对卡片 x 位置归一化为空间相位差（与 FlowFill 的 stop 同口径，
    // span 缺省 0.6 = 沿卡片横向铺开 0.6 圈色相）。传元素中心 x 与卡片宽。
    function spaceOffset(x, width, span) {
        if (!(width > 0))
            return 0
        return (x / width) * (span === undefined ? 0.6 : span)
    }

    // ── 整卡唯一互斥：确定性部位枚举与裁决 ────────────────────────────────
    // 一张卡只允许一个部位为流光（含卡片底色与表盘各子色位）。
    // 普通键按字母序；dials 数组按下标升序展开、字段序固定为
    // [dialBackground, dialColor, hourMinuteColor, secondColor]（与
    // dialslogic 的 fallback 表、SettingsRow 提示顺序一致）。
    // 路径格式：普通键 = 键名；表盘子色位 = "dials.<i>.<field>"。
    function flowSiteKeyOf(dialsKey, index, field) {
        return (dialsKey || "dials") + "." + index + "." + field
    }

    // 确定性有序遍历，返回第一个流光部位的路径；无流光返回空串
    function flowOwnerKey(config, dialsKey) {
        if (!config || typeof config !== "object")
            return ""
        var dk = dialsKey || "dials"
        var keys = []
        for (var k in config)
            keys.push(String(k))
        keys.sort()
        for (var i = 0; i < keys.length; ++i) {
            var key = keys[i]
            if (key === dk)
                continue
            if (root.isFlow(config[key]))
                return key
        }
        var list = config[dk]
        if (list && typeof list.length === "number") {
            var order = DialsLogic.dialFieldOrder()
            for (var d = 0; d < list.length; ++d) {
                var dial = list[d]
                if (!dial || typeof dial !== "object")
                    continue
                for (var f = 0; f < order.length; ++f) {
                    if (root.isFlow(dial[order[f]]))
                        return root.flowSiteKeyOf(dk, d, order[f])
                }
            }
        }
        return ""
    }

    // 某部位是否就是整卡唯一的流光 owner
    function flowSiteIsOwner(config, dialsKey, site) {
        return root.flowOwnerKey(config, dialsKey) === String(site)
    }

    // 写路径裁决：某部位当前是否被允许进入流光
    //（整卡已有其它部位占用流光 → 拒绝；本部位已占用则允许继续/退出）
    function flowGranted(config, dialsKey, site) {
        var owner = root.flowOwnerKey(config, dialsKey)
        return owner.length === 0 || owner === String(site)
    }

    // ── 渲染层兜底裁决：消费端统一取色入口 ────────────────────────────────
    // 一张卡只允许确定性的第一个流光部位实际以彩虹渲染；其余 @flow: 值一律
    // 回退为"该键未自定义时的浅色缺省值"（与设置面板落盘收敛一致），保持
    // 渲染与持久化配置在任何时刻一致。值非流光则原样走常规解析。
    // x/width 承载元素相对卡片 x 位置：多元素同卡时形成横向彩虹，单元素
    // 居中时 offset 恒定、随整卡共享相位跑马。
    // resolve 系：无明暗主题变体的纯色；theme 系：带亮/暗缺省的主题化取色。

    function resolveSiteColor(config, dialsKey, site, value, fallback, x, width, span) {
        if (!root.isFlow(value))
            return root.resolveColor(value, fallback)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return fallback
        return root.resolveColor(value, fallback, root.spaceOffset(x, width, span))
    }

    function themedSiteColor(config, dialsKey, site, value, lightDefault, darkDefault,
                             x, width, span) {
        if (!root.isFlow(value))
            return root.themedColor(value, lightDefault, darkDefault)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return root.dark ? darkDefault : lightDefault
        return root.themedColor(value, lightDefault, darkDefault,
                                root.spaceOffset(x, width, span))
    }

    function opaqueSiteColor(config, dialsKey, site, value, fallback, x, width, span) {
        if (!root.isFlow(value))
            return root.opaqueColor(value, fallback)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return fallback
        return root.opaqueColor(value, fallback, root.spaceOffset(x, width, span))
    }

    function themedOpaqueSiteColor(config, dialsKey, site, value, lightDefault,
                                   darkDefault, x, width, span) {
        if (!root.isFlow(value))
            return root.themedOpaqueColor(value, lightDefault, darkDefault)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return root.dark ? darkDefault : lightDefault
        return root.themedOpaqueColor(value, lightDefault, darkDefault,
                                      root.spaceOffset(x, width, span))
    }

    // Canvas 专用：低频相位（约 7.5fps），onPaint 内逐图元以自身 x 取色。
    function canvasSiteColor(config, dialsKey, site, value, fallback, x, width, span) {
        if (!root.isFlow(value))
            return root.resolveCanvasColor(value, fallback)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return fallback
        return root.resolveCanvasColor(value, fallback, root.spaceOffset(x, width, span))
    }

    function themedCanvasSiteColor(config, dialsKey, site, value, lightDefault,
                                   darkDefault, x, width, span) {
        if (!root.isFlow(value))
            return root.themedCanvasColor(value, lightDefault, darkDefault)
        if (!root.flowGranted(config, dialsKey, String(site)))
            return root.dark ? darkDefault : lightDefault
        return root.themedCanvasColor(value, lightDefault, darkDefault,
                                      root.spaceOffset(x, width, span))
    }
}
