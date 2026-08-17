// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import Qt5Compat.GraphicalEffects

// 圆角封面容器（播放器小组件拆分）：真实封面与 N/A 回退共用。
// 由调用方注入 artUrl/showCover/iconSource/coverSize。
Item {
    id: root

    property string artUrl: ""
    property bool showCover: true
    // 无封面占位图标源
    property string iconSource: ""
    property int coverSize: 64

    property bool coverFailed: false

    Image {
        id: coverImage
        anchors.fill: parent
        // source 只跟随 artUrl；coverFailed 只控制占位图标显示，
        // 避免 source 依赖 coverFailed 又在其变化时复位造成绑定循环。
        source: root.showCover ? root.artUrl : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: root.showCover
        // 仅在有真实封面时启用圆角遮罩图层，避免无封面时无谓离屏 FBO
        layer.enabled: root.showCover && root.artUrl.length > 0
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: coverImage.width
                height: coverImage.height
                radius: 6
            }
        }
        onStatusChanged: {
            if (status === Image.Error)
                root.coverFailed = true
        }
        onSourceChanged: root.coverFailed = false
    }

    Image {
        id: fallbackCover
        anchors.centerIn: parent
        width: root.coverSize * 0.56
        height: root.coverSize * 0.56
        source: root.iconSource
        sourceSize.width: root.coverSize * 0.56
        sourceSize.height: root.coverSize * 0.56
        visible: !root.showCover || root.artUrl.length === 0 || root.coverFailed
        opacity: 0.55
    }
}
