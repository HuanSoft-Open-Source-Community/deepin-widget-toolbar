// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "widgettypes.h"

#include <QRect>

// 4 列网格纯算法引擎（无状态、无持久化）：
// 空闲槽搜索、双向联动避让、布局比较等，供 WidgetManager 编排使用。
namespace WidgetGrid {

inline constexpr int kColumns = 4;

QRect instanceRect(const WidgetTypes::WidgetInstance &inst);
bool layoutEquals(const QList<WidgetTypes::WidgetInstance> &a,
                  const QList<WidgetTypes::WidgetInstance> &b);
// 把 inst 放入首个空闲矩形（不移动其它实例），放不下时追加到最底行下方
void placeFirstFree(WidgetTypes::WidgetInstance &inst,
                    const QList<WidgetTypes::WidgetInstance> &others);
// 双向联动避让：返回避让后的实例列表；fixedId 实例保持原位置（预览用），
// 其它实例保持 gridX，只调 gridY，向最近空闲行移动（中心在上→优先向上，否则向下）
QList<WidgetTypes::WidgetInstance> computeAvoidance(
    const QList<WidgetTypes::WidgetInstance> &instances,
    const QString &fixedId, int targetX, int targetY);

} // namespace WidgetGrid
