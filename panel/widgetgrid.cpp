// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "widgetgrid.h"

#include <QDebug>
#include <QRect>

namespace WidgetGrid {

QRect instanceRect(const WidgetTypes::WidgetInstance &inst)
{
    return QRect(inst.gridX, inst.gridY,
                 qBound(1, inst.cols, kColumns),
                 qMax(1, inst.rows));
}

bool layoutEquals(const QList<WidgetTypes::WidgetInstance> &a,
                  const QList<WidgetTypes::WidgetInstance> &b)
{
    if (a.size() != b.size())
        return false;
    for (int i = 0; i < a.size(); ++i) {
        const WidgetTypes::WidgetInstance &x = a.at(i);
        const WidgetTypes::WidgetInstance &y = b.at(i);
        if (x.instanceId != y.instanceId || x.gridX != y.gridX
            || x.gridY != y.gridY || x.cols != y.cols || x.rows != y.rows)
            return false;
    }
    return true;
}

void placeFirstFree(WidgetTypes::WidgetInstance &inst,
                    const QList<WidgetTypes::WidgetInstance> &others)
{
    inst.cols = qBound(1, inst.cols, kColumns);
    inst.rows = qMax(1, inst.rows);

    // 纵向不限行：扫描上界 = 现有内容最底行 + 待放置行数 + 1，保证一定能放下
    int maxBottom = 0;
    for (const WidgetTypes::WidgetInstance &other : others)
        maxBottom = qMax(maxBottom, other.gridY + qMax(1, other.rows));
    const int scanLimit = maxBottom + inst.rows + 1;

    for (int y = 0; y <= scanLimit; ++y) {
        for (int x = 0; x + inst.cols <= kColumns; ++x) {
            const QRect candidate(x, y, inst.cols, inst.rows);
            bool free = true;
            for (const WidgetTypes::WidgetInstance &other : others) {
                if (instanceRect(other).intersects(candidate)) {
                    free = false;
                    break;
                }
            }
            if (free) {
                inst.gridX = x;
                inst.gridY = y;
                return;
            }
        }
    }

    // 兜底：追加到现有内容最底行下方
    inst.gridX = 0;
    inst.gridY = maxBottom;
}

QList<WidgetTypes::WidgetInstance> computeAvoidance(
    const QList<WidgetTypes::WidgetInstance> &instances,
    const QString &fixedId, int targetX, int targetY)
{
    QList<WidgetTypes::WidgetInstance> result = instances;
    int fixedIndex = -1;
    for (int i = 0; i < result.size(); ++i) {
        if (result.at(i).instanceId == fixedId) {
            fixedIndex = i;
            break;
        }
    }
    if (fixedIndex < 0)
        return instances;

    // 固定实例（拖拽源）在返回布局中保持原位置，落位前不移动自身；
    // 避让冲突按目标矩形计算，其原占位视为可让出的空间（预览时表现为被让开的洞）。
    const WidgetTypes::WidgetInstance &fixedInst = result.at(fixedIndex);
    const QRect fixedRect(targetX, targetY,
                          qBound(1, fixedInst.cols, kColumns),
                          qMax(1, fixedInst.rows));

    int maxBottom = 0;
    for (const WidgetTypes::WidgetInstance &inst : result)
        maxBottom = qMax(maxBottom, inst.gridY + qMax(1, inst.rows));
    // 扫描上限覆盖现有内容与固定目标矩形：保证任何冲突实例都能在界内找到向下候选
    const int scanLimit = qMax(maxBottom, fixedRect.y() + fixedRect.height())
        + result.size() + 2;

    // 是否与固定目标或其它实例（不含固定实例自身）冲突
    auto hasConflict = [&](int index) {
        const QRect cur = instanceRect(result.at(index));
        if (cur.intersects(fixedRect))
            return true;
        for (int j = 0; j < result.size(); ++j) {
            if (j == index || j == fixedIndex)
                continue;
            if (cur.intersects(instanceRect(result.at(j))))
                return true;
        }
        return false;
    };

    // 最近空闲行：同距离优先偏好方向（中心在目标中心上方→上，否则→下）
    auto findFreeY = [&](int selfIndex, bool preferredUp) {
        const WidgetTypes::WidgetInstance &inst = result.at(selfIndex);
        const int rows = qMax(1, inst.rows);
        const int cols = qBound(1, inst.cols, kColumns);
        for (int dy = 1; dy <= scanLimit; ++dy) {
            for (int dir = 0; dir < 2; ++dir) {
                const bool up = dir == 0 ? preferredUp : !preferredUp;
                const int candidateY = up ? inst.gridY - dy : inst.gridY + dy;
                if (candidateY < 0 || candidateY > scanLimit)
                    continue;
                const QRect candidate(inst.gridX, candidateY, cols, rows);
                if (candidate.intersects(fixedRect))
                    continue;
                bool free = true;
                for (int j = 0; j < result.size() && free; ++j) {
                    if (j == selfIndex || j == fixedIndex)
                        continue;
                    free = !candidate.intersects(instanceRect(result.at(j)));
                }
                if (free)
                    return candidateY;
            }
        }
        return -1;
    };

    // 迭代松弛：所有冲突实例在同一轮同步找最近空闲行，直到无冲突
    const int maxPasses = 2 * result.size() + 1;
    for (int pass = 0; pass < maxPasses; ++pass) {
        bool changed = false;
        for (int i = 0; i < result.size(); ++i) {
            if (i == fixedIndex || !hasConflict(i))
                continue;
            const bool preferredUp =
                instanceRect(result.at(i)).center().y() < fixedRect.center().y();
            const int newY = findFreeY(i, preferredUp);
            if (newY >= 0 && newY != result.at(i).gridY) {
                result[i].gridY = newY;
                changed = true;
            }
        }
        if (!changed)
            return result;
    }

    // 兜底：仍冲突的实例依次堆到当前最底行下方（保证无冲突）
    int bottom = 0;
    for (const WidgetTypes::WidgetInstance &inst : result)
        bottom = qMax(bottom, inst.gridY + qMax(1, inst.rows));
    bottom = qMax(bottom, fixedRect.y() + fixedRect.height());
    for (int pass = 0; pass < maxPasses; ++pass) {
        bool changed = false;
        for (int i = 0; i < result.size(); ++i) {
            if (i == fixedIndex || !hasConflict(i))
                continue;
            result[i].gridY = bottom;
            bottom += qMax(1, result.at(i).rows);
            changed = true;
        }
        if (!changed)
            return result;
    }
    return result;
}

} // namespace WidgetGrid
