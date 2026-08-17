// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// 世界时间表盘列表的纯函数工具（从 worldtime 小组件拆分）：
// 缺省预置、尺寸变化时的补位/收缩计算；宿主单例（Timezones/WidgetHost）
// 经 options 传入，函数本身无副作用。

// 缺省四表盘：当前时区一块 + 老四样中不与当前时区重复的前三个
function defaultDialList(systemTimezone, userTimezones, legacyFourZones) {
    var system = systemTimezone
    if (system.length === 0 && userTimezones.length > 0)
        system = userTimezones[0]
    var zones = []
    if (system.length > 0)
        zones.push(system)
    for (var i = 0; i < legacyFourZones.length && zones.length < 4; i++) {
        if (legacyFourZones[i] !== system)
            zones.push(legacyFourZones[i])
    }
    var list = []
    for (var j = 0; j < zones.length; j++)
        list.push({ "zone": zones[j], "auto": false })
    return list
}

// 放大补位：从末位偏移 +1 小时、越过 +14 回绕到 -12、按偏移去重，
// 取该偏移下第一个未用时区生成补位表盘（auto=true）
function fillDials(current, target, options) {
    var list = current.slice()
    var usedZones = {}
    var usedOffsets = {}
    for (var i = 0; i < list.length; i++) {
        usedZones[list[i].zone] = true
        usedOffsets[options.zoneOffset(list[i].zone)] = true
    }

    // 跨实例唯一性：其它实例已用地区不参与补位
    var otherUsed = options.otherUsedZones || []
    for (var o = 0; o < otherUsed.length; o++)
        usedZones[otherUsed[o]] = true
    var excludeZones = []
    for (var used in usedZones)
        excludeZones.push(used)

    var cursor = list.length > 0
        ? Math.round(options.zoneOffset(list[list.length - 1].zone)) : 0
    var guard = 0
    while (list.length < target && guard < 200) {
        guard++
        cursor = cursor >= 14 ? -12 : cursor + 1
        if (usedOffsets[cursor] !== undefined)
            continue
        var zoneId = options.firstZoneForOffset(cursor, excludeZones)
        if (zoneId.length === 0 || usedZones[zoneId] !== undefined)
            continue
        usedZones[zoneId] = true
        excludeZones.push(zoneId)
        usedOffsets[cursor] = true
        list.push({ "zone": zoneId, "auto": true })
    }
    return list
}

// 缩小：从尾部删除补位表盘（auto=true），用户表盘保留
function shrinkDials(current, target) {
    var list = current.slice()
    while (list.length > target && list[list.length - 1].auto === true)
        list.pop()
    return list
}
