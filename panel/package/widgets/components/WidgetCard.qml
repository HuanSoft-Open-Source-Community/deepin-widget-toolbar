// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.dtk 1.0

// 内置小组件统一卡片：背景、圆角、标准内容边距与裁剪。
// 子内容默认放进 contentContainer，由卡片负责 10px 内边距和防溢出。
Item {
    id: root

    property int margin: 10
    property int hostCols: 0
    property int hostRows: 0
    default property alias contentData: contentContainer.data

    clip: true

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: root.margin
        clip: true
    }
}
