// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// 世界时间"表盘列表"（timezoneList 类型配置）的纯函数工具：
// 从小组件配置面板拆分出的行模型计算，全部为无副作用函数，
// 由配置面板包装后调用 control.commit 落盘。

// 与 ColorUtils 相同的颜色校验规则（避免跨模块依赖）
function resolveColor(value, fallback) {
    if (typeof value === "string" && /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value))
        return value
    return fallback
}

// 配置中 key 对应的表盘数组；非数组（缺失/旧数据）一律回退空数组，
// 防止数值被 Repeater 当成重复次数实例化大量委托
function dialList(values, key) {
    var list = values[key]
    return list && list.length !== undefined ? list : []
}

// 其它实例已用地区集合（跨实例唯一性）
function usedZoneSet(usedZones) {
    var set = {}
    for (var i = 0; i < usedZones.length; i++)
        set[usedZones[i]] = true
    return set
}

// 单行下拉选项：过滤其它实例已用地区，但保留本行当前地区（旧配置可见）
function rowOptions(usedZones, values, zoneOptions, key, index) {
    var used = usedZoneSet(usedZones)
    var list = dialList(values, key)
    var dial = index < list.length ? list[index] : null
    var zone = dial && dial.zone ? dial.zone : ""
    var result = []
    for (var i = 0; i < zoneOptions.length; i++) {
        var value = zoneOptions[i].value
        if (used[value] === undefined || value === zone)
            result.push(zoneOptions[i])
    }
    return result
}

function zoneIndex(usedZones, values, zoneOptions, key, index) {
    var options = rowOptions(usedZones, values, zoneOptions, key, index)
    var list = dialList(values, key)
    var dial = index < list.length ? list[index] : null
    var zone = dial && dial.zone ? dial.zone : ""
    for (var i = 0; i < options.length; i++) {
        if (options[i].value === zone)
            return i
    }
    return 0
}

// 添加一块新表盘：优先当前时区，已被占用则取第一个未用地区；
// 无可用地区返回 null。新用户表盘插到补位表盘之前，
// 保证补位表盘始终是尾部可回收的 padding。
function addDial(values, usedZones, zoneOptions, systemTimezone, key) {
    var list = dialList(values, key).slice()
    var used = usedZoneSet(usedZones)
    // 本实例已用地区也不能重复添加：先加了当前时区后，
    // 下一次添加应缺省到别的时区
    for (var i = 0; i < list.length; i++) {
        if (list[i] && typeof list[i].zone === "string" && list[i].zone.length > 0)
            used[list[i].zone] = true
    }
    var defaultZone = systemTimezone
    if (defaultZone.length === 0 || used[defaultZone] !== undefined) {
        defaultZone = ""
        for (var j = 0; j < zoneOptions.length; j++) {
            if (used[zoneOptions[j].value] === undefined) {
                defaultZone = zoneOptions[j].value
                break
            }
        }
    }
    if (defaultZone.length === 0)
        return null

    var insertAt = list.length
    for (var k = 0; k < list.length; k++) {
        if (list[k].auto === true) {
            insertAt = k
            break
        }
    }
    list.splice(insertAt, 0, { "zone": defaultZone, "auto": false })
    return list
}

function removeDial(values, key, index) {
    var list = dialList(values, key).slice()
    if (index < 0 || index >= list.length)
        return null
    list.splice(index, 1)
    return list
}

// 改选时区：其它实例已用地区不允许改选进来（返回 null 表示拒绝）；
// 用户改过的补位表盘视为用户表盘，缩放缩小时不再删除
function setDialZone(usedZones, values, key, index, zone) {
    var list = dialList(values, key).slice()
    if (index < 0 || index >= list.length)
        return null
    if (usedZoneSet(usedZones)[zone] !== undefined)
        return null
    list[index] = { "zone": zone, "auto": false }
    return list
}

// 单块表盘的字段色值；未设置时回退到对应全局配置
function dialColorValue(values, list, index, field) {
    var dial = index < list.length ? list[index] : null
    var value = dial ? dial[field] : undefined
    var fallback = "#ffffff"
    if (field === "dialColor")
        fallback = values.dialColor || "#000000"
    else if (field === "hourMinuteColor")
        fallback = values.hourMinuteHandColor || "#000000"
    else if (field === "secondColor")
        fallback = values.secondHandColor || "#ff4d4f"
    else if (field === "dialBackground")
        fallback = values.dialBackgroundColor || "#ffffff"
    return resolveColor(value, fallback)
}

function commitDialColor(values, key, index, field, value) {
    var list = dialList(values, key).slice()
    if (index < 0 || index >= list.length)
        return null
    var dial = {}
    for (var k in list[index])
        dial[k] = list[index][k]
    dial[field] = value
    list[index] = dial
    return list
}
