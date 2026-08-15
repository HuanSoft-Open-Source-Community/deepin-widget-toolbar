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
    // 宿主注入的实例配置与标识；基类先声明，主面板 Binding 才能稳定写入。
    property var widgetConfig: ({})
    property string instanceId: ""
    // 主题色：各小组件从 widgetConfig 解析后注入；palette 设置会传递给子内容
    property color backgroundColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#1e1e1e" : "#f5f5f5"
    // 默认值必须不依赖 palette：palette 又由本卡片的这些属性反向级联，
    // 若默认值引用 palette 会形成循环绑定，且子类型重声明也无法修正基类内部读取。
    property color textColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#e8e8e8" : "#1a1a1a"
    property color highlightColor: DTK.themeType === ApplicationHelper.DarkType
        ? "#4d8cff" : "#0081ff"
    property color highlightedTextColor: "#ffffff"
    property bool transparentBackground: false
    // 宿主注入的实例数据目录；由主面板的 Binding 写入，供持久化组件使用。
    property string dataDir: ""
    default property alias contentData: contentContainer.data

    clip: true
    palette.windowText: root.textColor
    palette.highlight: root.highlightColor
    palette.highlightedText: root.highlightedTextColor

    Rectangle {
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        visible: !root.transparentBackground
        color: root.backgroundColor
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: root.margin
        clip: true
    }
}
