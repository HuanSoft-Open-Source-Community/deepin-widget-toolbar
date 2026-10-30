// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// 内部对象只引用本文件 root（ShaderEffect 注入），绑定式作用域更安全，
// 同时消除 qmllint 对嵌套对象引用外部 id 的 Unqualified access 告警
pragma ComponentBehavior: Bound

// 流光文本：整卡唯一的流光部位为「文字」时，用 layer + ShaderEffect 让单条
// 文本内部呈现「横向空间渐变 + 相位跑马」的彩虹效果。
//
// 背景：QML 的 Text.color 是单值颜色，无法直接画渐变笔画；寄存器级别的"按
// 元素 x 位置采样色相"在多文字元素同卡时可近似出横向彩虹（见各 widget 对
// resolveColor 传入 spaceOffset 的用法），但单条居中/单区块的大号文字内部仍
// 是整块一个颜色。FlowText 用 ShaderEffect 在字形内部逐像素做
// hue(base) + phase + x*span 的渐变，给出真正段内彩虹。
//
// 用法（仅流光 owner 启用；静态色时 layer 关闭，零额外开销）：
//
//     Components.FlowText {
//         Layout.fillWidth: true
//         text: "12:00"
//         flowGradient: ownerIsFlow
//         flowBaseColor: Components.ColorUtils.flowBase(root.cfg.textColor,
//             fallback)   // owner 部位才传流光原色
//         flowPhaseValue: Components.ColorUtils.flowPhase
//         flowDark: Components.ColorUtils.dark
//         // 静态色时照常使用 color 属性
//         color: "..."
//     }
//
// 宿主接线口径（段内渐变与全卡 0.6 跨度口径连续，见 spec「术语与统一口径」）：
//   flowOffset = ColorUtils.spaceOffset(元素左缘相对卡片x, 卡片宽)
//   flowSpan   = ColorUtils.spaceOffset(元素宽, 卡片宽)
// 即元素内部沿 uv.x 铺开"元素宽占卡片宽的那一段"色相，与同卡其他元素按
// 各自 x 的采样无缝衔接；单块居中文字 left-x 恒定，仍随整卡相位跑马。
Text {
    id: root

    // 是否启用流光渐变（整卡互斥裁决后由宿主注入；非 owner 恒为 false）
    property bool flowGradient: false
    // 流光内嵌原色（owner 部位的 flowBase）；静态色时无需关心
    property color flowBaseColor: "#4d8cff"
    // 共享流光相位（0..1）与明暗主题标识，由宿主注入
    property real flowPhaseValue: 0
    property bool flowDark: false
    // 横向色相跨度（宿主按 spaceOffset(元素宽, 卡片宽) 注入；缺省 0.6
    // 与 FlowFill / ColorUtils.spaceOffset 全卡口径一致）
    property real flowSpan: 0.6
    // 元素左缘的空间相位偏移：spaceOffset(元素左缘相对卡片x, 卡片宽)，
    // 使段内渐变起点与全卡横向彩虹连续（宿主未注入时恒 0，退化为整块跑马）
    property real flowOffset: 0

    // 渐变时字形以纯白渲染，由 shader 上色并保留 alpha
    layer.enabled: root.flowGradient
    layer.effect: ShaderEffect {
        id: effect
        // layer 内容自动注入到名为 source 的 sampler
        property color glow: root.flowBaseColor
        property real phase: root.flowPhaseValue
        property real span: root.flowSpan
        property real offset: root.flowOffset
        property real darkF: root.flowDark ? 1.0 : 0.0

        fragmentShader: "
        varying highp vec2 qt_TexCoord0;
        uniform sampler2D source;
        uniform lowp float qt_Opacity;
        uniform vec4 glow;
        uniform float phase;
        uniform float span;
        uniform float offset;
        uniform float darkF;

        highp float hueFromRgb(vec3 c) {
            highp float maxc = max(c.r, max(c.g, c.b));
            highp float minc = min(c.r, min(c.g, c.b));
            highp float d = maxc - minc;
            if (d < 0.0001)
                return 0.0;
            highp float h;
            if (maxc == c.r)
                h = mod((c.g - c.b) / d, 6.0);
            else if (maxc == c.g)
                h = (c.b - c.r) / d + 2.0;
            else
                h = (c.r - c.g) / d + 4.0;
            h /= 6.0;
            return h < 0.0 ? h + 1.0 : h;
        }

        vec3 hsl2rgb(float h, float s, float l) {
            vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
                0.0, 1.0);
            return l + s * (k - 0.5) * (1.0 - abs(2.0 * l - 1.0));
        }

        void main() {
            vec4 tex = texture2D(source, qt_TexCoord0);
            if (tex.a < 0.02) {
                gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
                return;
            }
            // 上色 = 基准色相 + 共享相位 + 左缘空间偏移 + 段内横向渐变
            highp float h = hueFromRgb(glow.rgb) + phase + offset
                + qt_TexCoord0.x * span;
            h -= floor(h);
            vec3 col = hsl2rgb(h, 0.78, darkF > 0.5 ? 0.62 : 0.50);
            gl_FragColor = vec4(col, tex.a) * qt_Opacity;
        }
        "
    }
}