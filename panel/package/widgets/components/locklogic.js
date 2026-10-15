// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// lockWhen 声明式设置联动的纯函数引擎（宿主 API 1.11）：
// manifest 设置项可声明 lockWhen: {key: 源键, is: 触发值, as: 锁定值}，
// 语义"源值等于触发值时，本项（目标）被锁定为 as"。与 dialslogic.js 同法，
// 全部为无副作用/就地小步函数，由配置面板包装后随 commit 一次落盘；
// 引擎不感知任何具体键名与组件名，纯 schema 声明驱动。
//
// 状态机（源 S、目标 T、触发值 W、锁定值 L，记忆键 _lk_<键> 为内部键）：
//   E1 S→W：进入触发值的瞬间记忆锁定前样式 _lk_T（旧 T≠L 才记）与调整前
//          宽度 _lk_S；随后强制 T:=L（保持"源处触发值 ⇒ 目标处锁定值"不变式）。
//   E2 S W→≠W：离开触发值的瞬间，若 T 仍处锁定值：有有效记忆（≠L 且在 options
//          内）则恢复 T:=_lk_T；记忆缺失/非法一律保底回退（T 的 default，default
//          也退化则 options 首个非锁定值——宽度已有值，边框必须有可见样式）；
//          无论用否都清除 _lk_T/_lk_S。
//   E3 T L→X≠L 且 S 仍==W：锁定期间手动脱离 → 源回退 S:=_lk_S（有记录且≠W），
//          无记录回退源项 schema default；清除 _lk_S/_lk_T（T 已是手动新值）。
//   E4 T →L：手动设为锁定值——同步把源置为触发值（宽度随"无边框"归零），并
//          双向记忆：_lk_S=调整前源值（供 E3 改样式回退）、_lk_T=切换前样式
//          （触发条件已保证旧 T≠L，切入即有效记忆，供 E2 升宽恢复——无此记忆
//          时"样式 a→无边框→拖宽"会错落保底缺省，点线被还原成实线）。
//          重复选同锁定值（旧 T 已是 L）不触发、不写记忆。
//
// 级联深度恒为 1：只按本次 changedKey 处理对应方向的规则，引擎写入的键
// 不再二次触发规则（E1 写 T 不会触发 E3），成环声明也不会死循环。

// 值等值比较：数值语义优先（slider/integer 的 0 与 "0" 同值），
// 任一侧不可转有限数时退化为字符串严格比较（enum 值、布尔等）
function eq(a, b) {
    var na = Number(a)
    var nb = Number(b)
    if (a !== undefined && b !== undefined && isFinite(na) && isFinite(nb))
        return na === nb
    return String(a) === String(b)
}

// schema 中按 key 取项；不存在返回 null
function entryOf(schema, key) {
    for (var i = 0; i < schema.length; ++i) {
        if (schema[i].key === key)
            return schema[i]
    }
    return null
}

// 值是否出现在 entry 的 options 候选中
function hasOption(entry, value) {
    var opts = entry.options ? entry.options : []
    for (var i = 0; i < opts.length; ++i)
        if (eq(opts[i].value, value))
            return true
    return false
}

// 目标项的保底样式（E2 无有效记忆时用）：宽度已有值 ⇒ 边框必须有可见样式。
// 顺序：项 default（合法：≠锁定值且在 options）→ options 里首个 ≠锁定值 →
// undefined（全是退化数据：options 仅剩锁定项，调用方保持原值不动）
function fallbackStyle(entry, L) {
    if (entry.default !== undefined && !eq(entry.default, L)
            && hasOption(entry, entry.default))
        return entry.default
    var opts = entry.options ? entry.options : []
    for (var i = 0; i < opts.length; ++i)
        if (!eq(opts[i].value, L))
            return opts[i].value
    return undefined
}

// lockWhen 声明合法性（防御第三方写错 manifest）：
// - 必须是对象且 key/is/as 三要素齐备；
// - 源键必须存在于 schema（且不得自指）；
// - 目标必须是带 options 的 enum，as 值在 options 内；
// - 源为数值类型（slider/integer）时 is 必须可转有限数。
// 返回 "" 表示合法；否则返回失败原因（调用方据此告警）。
function validateLock(schema, targetKey) {
    var t = entryOf(schema, targetKey)
    if (!t || t.lockWhen === undefined)
        return "missing-target"
    var decl = t.lockWhen
    if (typeof decl !== "object" || decl === null
            || decl.key === undefined || decl.is === undefined
            || decl.as === undefined)
        return "incomplete-decl"
    if (String(decl.key) === String(targetKey))
        return "self-lock"
    var s = entryOf(schema, String(decl.key))
    if (!s)
        return "unknown-source"
    var opts = t.options ? t.options : []
    if (t.type !== "enum" || opts.length === 0)
        return "target-not-enum"
    var found = false
    for (var i = 0; i < opts.length; ++i) {
        if (eq(opts[i].value, decl.as)) {
            found = true
            break
        }
    }
    if (!found)
        return "as-not-in-options"
    if ((s.type === "slider" || s.type === "integer") && !isFinite(Number(decl.is)))
        return "is-not-numeric"
    return ""
}

// 引擎主入口：oldValues 为提交前快照，next 为已写入本次变更的拷贝（就地修改），
// changedKey 为用户本次改动的键。schema 无 lockWhen 声明时零改动（零行为变化）。
function applyLocks(schema, oldValues, next, changedKey) {
    for (var i = 0; i < schema.length; ++i) {
        var t = schema[i]
        if (t.lockWhen === undefined)
            continue
        if (validateLock(schema, t.key) !== "")
            continue   // 非法声明跳过（告警去重由面板包装层负责）
        var decl = t.lockWhen
        var S = String(decl.key)
        var T = String(t.key)
        var W = decl.is
        var L = decl.as
        var memT = "_lk_" + T
        var memS = "_lk_" + S

        if (changedKey === S) {
            if (eq(next[S], W)) {
                // E1：进入触发值的瞬间记双份记忆，随后强制目标为锁定值
                if (!eq(oldValues[S], W)) {
                    if (!eq(oldValues[T], L))
                        next[memT] = oldValues[T]
                    next[memS] = oldValues[S]
                }
                if (!eq(next[T], L))
                    next[T] = L
            } else if (eq(oldValues[S], W)) {
                // E2：离开触发值——目标仍是锁定值时先恢复有效记忆（≠L 且在 options
                // 内），记忆缺失/非法一律保底回退（default→首个非锁定项，见
                // fallbackStyle）；目标已是其它值则不动。记忆无论用否均清除。
                // 注：oldValues 是 commit 前的 instanceConfig 快照——E1/E4 的锁定
                // 落盘在先，用户随后拖滑块时 oldValues[S] 已是触发值 W，判定成立。
                if (eq(next[T], L)) {
                    var fb = (next[memT] !== undefined && !eq(next[memT], L)
                              && hasOption(t, next[memT]))
                        ? next[memT] : fallbackStyle(t, L)
                    if (fb !== undefined)
                        next[T] = fb
                }
                delete next[memT]
                delete next[memS]
            }
        } else if (changedKey === T) {
            if (!eq(next[T], L) && eq(next[S], W)) {
                // E3：锁定期间手动脱离目标 → 源回退调整前记忆，缺省回退源 default
                var srcEntry = entryOf(schema, S)
                var dflt = srcEntry && srcEntry.default !== undefined ? srcEntry.default : 0
                var back = next[memS]
                next[S] = (back !== undefined && !eq(back, W)) ? back : dflt
                delete next[memS]
                delete next[memT]
            } else if (eq(next[T], L) && !eq(oldValues[T] !== undefined ? oldValues[T] : next[T], L)
                       && !eq(next[S], W)) {
                // E4：手动选锁定值（从其它样式切入）→ 源归入触发值，双向记忆：
                // _lk_S=调整前源值（E3 回退用）、_lk_T=切换前样式（E2 升宽恢复用）。
                // 重复选同锁定值不触发（oldValues[T] 已是 L），不覆盖既有记忆。
                next[memS] = next[S]
                next[memT] = oldValues[T]
                next[S] = W
            }
        }
    }
}
