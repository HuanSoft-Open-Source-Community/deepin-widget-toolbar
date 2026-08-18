// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

pragma Singleton
import QtQuick

// 颜色安全工具：所有来自用户配置的颜色必须先经这里校验，
// 只接受 #RRGGBB / #AARRGGBB，非法值回退到调用方提供的默认色。
QtObject {
    function isValidColor(value) {
        return typeof value === "string"
            && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)
    }

    function resolveColor(value, fallback) {
        return isValidColor(value) ? value : fallback
    }

    // 卡片底色专用：透明背景开关关闭时底色必须不透明，
    // 防止旧实例里保存的半透明色让卡片露出“白边/底色不生效”的观感。
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
}