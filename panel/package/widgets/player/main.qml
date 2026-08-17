// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置小组件：MPRIS 播放控制器（默认 4×2）
// 曲目/封面/播放控制全部来自宿主 MediaPlayer 代理；
// 无媒体时始终显示占位卡片（N/A 封面 + “无歌曲”提示）。
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    property string playerMode: widgetConfig && widgetConfig.playerMode
        ? widgetConfig.playerMode : "auto"
    property string lockedPlayer: widgetConfig && widgetConfig.lockedPlayer
        ? widgetConfig.lockedPlayer : ""
    property bool showCover: widgetConfig && widgetConfig.showCover !== undefined
        ? widgetConfig.showCover : true
    property bool showControls: widgetConfig && widgetConfig.showControls !== undefined
        ? widgetConfig.showControls : true
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    backgroundColor: Components.ColorUtils.opaqueColor(
        widgetConfig && widgetConfig.backgroundColor, "#00bcd4")
    textColor: Components.ColorUtils.resolveColor(
        widgetConfig && widgetConfig.textColor, "#1a1a1a")

    MediaPlayer {
        id: player
        mode: root.playerMode
        service: root.lockedPlayer
    }

    readonly property bool hasMedia: player.connected
        && player.hasTrack && player.playbackStatus !== "Stopped"
    // 尺寸命名与右键菜单一致：中=2×2，宽=4×2，大=4×4
    readonly property bool large: hostRows >= 4
    readonly property bool wide: hostCols >= 4
    readonly property bool medium: !root.large && !root.wide
    readonly property bool wideCard: root.wide && !root.large
    // 宽布局封面约占内容宽度 2/5，收窄右侧文字列，避免留白过多
    readonly property int coverSize: root.large ? 160
        : (root.wideCard ? Math.round((root.width - root.margin * 2) * 0.4) : 64)
    readonly property int titlePixelSize: root.large ? 20 : (root.wideCard ? 17 : 15)
    readonly property int artistPixelSize: root.large ? 14 : (root.wideCard ? 13 : 11)
    readonly property int controlSize: root.large ? 40 : 28
    readonly property int controlSpacing: root.large ? 24 : (root.wideCard ? 16 : 14)
    readonly property int verticalSpacing: root.large ? 14 : 12
    readonly property color hoverFill: DTK.themeType === ApplicationHelper.DarkType
        ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color pressFill: DTK.themeType === ApplicationHelper.DarkType
        ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14)

    function icon(name) {
        var variant = DTK.themeType === ApplicationHelper.DarkType ? "dark" : "light"
        return "qrc:/widgets/player/icons/" + name + "-" + variant + ".svg"
    }

    // 当前 hover/按下的控制按钮索引（0=上一曲，1=播放/暂停，2=下一曲）；-1 表示不在按钮上。
    // 面板拖放层会拦截小组件内部鼠标事件，按钮交互状态由宿主回调驱动。
    property int hoveredControl: -1
    property int pressedControl: -1

    // 当前可见的控制条（中/宽/大三选一）
    function currentControlsRow() {
        if (root.medium && mediumControls.visible)
            return mediumControls
        if (root.wideCard && wideControls.visible)
            return wideControls
        if (root.large && largeControls.visible)
            return largeControls
        return null
    }

    // 把宿主传入的组件内坐标换算成按钮索引；落在按钮间距外返回 -1
    function controlIndexAt(x, y) {
        var row = root.currentControlsRow()
        if (!row)
            return -1
        var local = row.mapFromItem(root, x, y)
        var cell = root.controlSize + root.controlSpacing
        if (local.x < 0 || local.y < 0
            || local.x >= row.width || local.y >= row.height)
            return -1
        var index = Math.floor(local.x / cell)
        if (index < 0 || index > 2 || local.x % cell >= root.controlSize)
            return -1
        return index
    }

    // 宿主回调：拖放层把按下/悬停/松开/点击转发给交互型小组件
    function handleHostPressed(x, y) {
        root.pressedControl = root.controlIndexAt(x, y)
    }
    function handleHostHover(x, y) {
        root.hoveredControl = root.controlIndexAt(x, y)
        if (root.pressedControl >= 0 && root.hoveredControl < 0)
            root.pressedControl = -1
    }
    function handleHostReleased(x, y) {
        root.pressedControl = -1
    }
    function handleHostClick(x, y) {
        var index = root.controlIndexAt(x, y)
        if (index < 0)
            return
        switch (index) {
        case 0:
            if (player.canGoPrevious)
                player.previous()
            break
        case 1:
            if (player.canControl && (player.canPlay || player.canPause))
                player.playPause()
            break
        case 2:
            if (player.canGoNext)
                player.next()
            break
        }
    }

    // 封面与控制条已拆分为 Components.CoverArt / Components.ControlsBar

    // 无媒体占位：没有播放曲目时始终显示
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: !root.hasMedia

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.large ? 64 : 48
            height: root.large ? 64 : 48
            source: root.icon("na")
            sourceSize.width: root.large ? 64 : 48
            sourceSize.height: root.large ? 64 : 48
            opacity: 0.7
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("No song playing")
            font: DTK.fontManager.t6
            color: root.textColor
            opacity: 0.7
        }
    }

    // 2×2 中：封面 + 完整控制三件套，上下居中，不显示文字
    Column {
        anchors.centerIn: parent
        spacing: root.verticalSpacing
        visible: root.hasMedia && root.medium

        Components.CoverArt {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showCover
            width: root.coverSize
            height: root.coverSize
            artUrl: player.artUrl
            showCover: root.showCover
            iconSource: root.icon("na")
            coverSize: root.coverSize
        }

        Components.ControlsBar {
            id: mediumControls
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showControls
            controlSize: root.controlSize
            controlSpacing: root.controlSpacing
            hoveredControl: root.hoveredControl
            pressedControl: root.pressedControl
            hoverFill: root.hoverFill
            pressFill: root.pressFill
            canGoPrevious: player.canGoPrevious
            canControl: player.canControl
            canPlay: player.canPlay
            canPause: player.canPause
            canGoNext: player.canGoNext
            playing: player.playbackStatus === "Playing"
            prevIcon: root.icon("prev")
            playIcon: root.icon("play")
            pauseIcon: root.icon("pause")
            nextIcon: root.icon("next")
        }
    }

    // 4×2 宽：保持左右布局（封面左，标题/艺术家/控件右上中下）
    RowLayout {
        anchors.fill: parent
        spacing: 12
        visible: root.hasMedia && root.wideCard

        Components.CoverArt {
            visible: root.showCover
            Layout.preferredWidth: root.coverSize
            Layout.preferredHeight: root.coverSize
            Layout.alignment: Qt.AlignVCenter
            artUrl: player.artUrl
            showCover: root.showCover
            iconSource: root.icon("na")
            coverSize: root.coverSize
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: player.title.length > 0 ? player.title : qsTr("Unknown title")
                font.pixelSize: root.titlePixelSize
                font.weight: Font.DemiBold
                color: root.textColor
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.Wrap
                lineHeight: 1.15
            }

            Text {
                Layout.fillWidth: true
                text: player.artist.length > 0 ? player.artist : qsTr("Unknown artist")
                font.pixelSize: root.artistPixelSize
                color: root.textColor
                opacity: 0.65
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // 弹性空隙：把控件推到卡片底部（信息靠上、控件靠下的经典布局）
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
            }

            Components.ControlsBar {
                id: wideControls
                visible: root.showControls
                width: root.controlSize * 3 + root.controlSpacing * 2
                height: root.controlSize
                controlSize: root.controlSize
                controlSpacing: root.controlSpacing
                hoveredControl: root.hoveredControl
                pressedControl: root.pressedControl
                hoverFill: root.hoverFill
                pressFill: root.pressFill
                canGoPrevious: player.canGoPrevious
                canControl: player.canControl
                canPlay: player.canPlay
                canPause: player.canPause
                canGoNext: player.canGoNext
                playing: player.playbackStatus === "Playing"
                prevIcon: root.icon("prev")
                playIcon: root.icon("play")
                pauseIcon: root.icon("pause")
                nextIcon: root.icon("next")
            }
        }
    }

    // 4×4 大：居中上下布局，封面/文字/控件全部水平居中
    Column {
        anchors.centerIn: parent
        spacing: root.verticalSpacing
        visible: root.hasMedia && root.large

        Components.CoverArt {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showCover
            width: root.coverSize
            height: root.coverSize
            artUrl: player.artUrl
            showCover: root.showCover
            iconSource: root.icon("na")
            coverSize: root.coverSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - root.margin * 2
            text: player.title.length > 0 ? player.title : qsTr("Unknown title")
            font.pixelSize: root.titlePixelSize
            font.weight: Font.DemiBold
            color: root.textColor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            lineHeight: 1.15
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - root.margin * 2
            text: player.artist.length > 0 ? player.artist : qsTr("Unknown artist")
            font.pixelSize: root.artistPixelSize
            color: root.textColor
            opacity: 0.65
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Components.ControlsBar {
            id: largeControls
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showControls
            width: root.controlSize * 3 + root.controlSpacing * 2
            height: root.controlSize
            controlSize: root.controlSize
            controlSpacing: root.controlSpacing
            hoveredControl: root.hoveredControl
            pressedControl: root.pressedControl
            hoverFill: root.hoverFill
            pressFill: root.pressFill
            canGoPrevious: player.canGoPrevious
            canControl: player.canControl
            canPlay: player.canPlay
            canPause: player.canPause
            canGoNext: player.canGoNext
            playing: player.playbackStatus === "Playing"
            prevIcon: root.icon("prev")
            playIcon: root.icon("play")
            pauseIcon: root.icon("pause")
            nextIcon: root.icon("next")
        }
    }
}
