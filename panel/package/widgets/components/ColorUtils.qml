// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

pragma Singleton
import QtQuick
import org.deepin.dtk 1.0

// 颜色安全工具：所有来自用户配置的颜色必须先经这里校验，
// 只接受 #RRGGBB / #AARRGGBB，非法值回退到调用方提供的默认色。
// 另提供"主题化默认色"：默认预设随明/暗主题切换（用户自定义色仍优先生效）。
QtObject {
    // 当前是否为暗色主题（绑定，主题切换时自动重算）
    readonly property bool dark: DTK.themeType === ApplicationHelper.DarkType

    function isValidColor(value) {
        return typeof value === "string"
            && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)
    }

    function resolveColor(value, fallback) {
        return isValidColor(value) ? value : fallback
    }

    // 主题化默认色：用户配置值（且与浅色默认值不同）优先，否则按当前主题取默认。
    // 判定"未自定义"用"是否等于浅色默认值"：宿主 instanceConfig 会把 manifest 的
    // default 一并写入实例配置，内置组件读到的配置值恒不为空，无法区分"未设置"；
    // 代价是用户刻意选中与浅色默认完全相同的颜色时，暗色下会显示暗色变体。
    function themedColor(value, lightDefault, darkDefault) {
        if (isValidColor(value) && value !== lightDefault)
            return value
        return dark ? darkDefault : lightDefault
    }

    // 卡片底色专用：透明背景开关关闭时底色必须不透明，
    // 防止旧实例里保存的半透明色让卡片露出"白边/底色不生效"的观感。
    // 8 位色为 #AARRGGBB：RRGGBB 是第 3~8 个字符（slice(3, 9)）；
    // 取 slice(1, 7) 会把 AA+RR+GG 拼成新 RGB，导致底色错位
    //（如粉 #ffffc0cb 变黄、紫 #ff8b5cf6 变橙）。
    function opaqueColor(value, fallback) {
        var color = resolveColor(value, fallback)
        if (typeof color !== "string")
            return color
        var match = /^#([0-9a-fA-F]{8})$/.exec(color)
        if (match)
            return "#ff" + color.slice(3, 9)
        return color
    }

    // 主题化 + 不透明化（卡片底色用）
    function themedOpaqueColor(value, lightDefault, darkDefault) {
        return opaqueColor(themedColor(value, lightDefault, darkDefault), darkDefault)
    }

    // 中性细描边（色卡/缩略图等）：亮色叠黑、暗色叠白，避免暗色下黑框不可见
    readonly property color hairline: dark
        ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.25)
}
