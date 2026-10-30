// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 卡片背景/预览块的流光填充：横向渐变，颜色随共享相位跑马。
// 只有大面积元素用它；高频小元素用纯色相位波，避免大量渐变重建。
Rectangle {
    id: root

    property string baseColor: "#4d8cff"   // 纯色原色（不含 @flow: 前缀）
    property real offset: 0                // 空间相位差
    property int stopCount: 9

    // 单个 stop 的取色：位置换算成空间相位差（铺满整条的色相跨度），
    // 再由 ColorUtils 的共享相位驱动色相循环；不做缓存，绑定即刷新。
    function stopColor(pos) {
        return ColorUtils.flowColorAt(root.baseColor, ColorUtils.flowPhase,
                                      root.offset + pos * 0.6, ColorUtils.dark)
    }

    // 9 个静态 GradientStop，position 固定，仅 color 参与绑定；
    // 首尾色相连续（色相环循环），中间不留断口。
    gradient: Gradient {
        orientation: Gradient.Horizontal

        GradientStop { position: 0.000; color: root.stopColor(0.000) }
        GradientStop { position: 0.125; color: root.stopColor(0.125) }
        GradientStop { position: 0.250; color: root.stopColor(0.250) }
        GradientStop { position: 0.375; color: root.stopColor(0.375) }
        GradientStop { position: 0.500; color: root.stopColor(0.500) }
        GradientStop { position: 0.625; color: root.stopColor(0.625) }
        GradientStop { position: 0.750; color: root.stopColor(0.750) }
        GradientStop { position: 0.875; color: root.stopColor(0.875) }
        GradientStop { position: 1.000; color: root.stopColor(1.000) }
    }
}
