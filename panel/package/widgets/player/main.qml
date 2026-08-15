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
    // 宽布局封面约占内容宽度 1/3，避免右侧留白过多
    readonly property int coverSize: root.large ? 160
        : (root.wideCard ? Math.round((root.width - root.margin * 2) / 3) : 64)
    readonly property int titlePixelSize: root.large ? 20 : 15
    readonly property int artistPixelSize: root.large ? 14 : 11
    readonly property int controlSize: root.large ? 40 : 28
    readonly property int controlSpacing: root.large ? 24 : (root.wideCard ? 16 : 14)
    readonly property int verticalSpacing: root.large ? 14 : 12
    readonly property int gapLimit: 16
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

    // 当前可见的控制条 Loader（中/宽/大三选一）
    function currentControlsRow() {
        if (root.medium && mediumControls.active)
            return mediumControls.item
        if (root.wideCard && wideControls.active)
            return wideControls.item
        if (root.large && largeControls.active)
            return largeControls.item
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

    // 圆角封面容器：真实封面与 N/A 回退共用
    Component {
        id: coverComponent

        Item {
            id: coverRoot
            anchors.fill: parent

            property bool coverFailed: false

            Image {
                id: coverImage
                anchors.fill: parent
                // source 只跟随 artUrl；coverFailed 只控制占位图标显示，
                // 避免 source 依赖 coverFailed 又在其变化时复位造成绑定循环。
                source: root.showCover ? player.artUrl : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: root.showCover
                layer.enabled: true
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
                        coverRoot.coverFailed = true
                }
                onSourceChanged: coverRoot.coverFailed = false
            }

            Image {
                id: fallbackCover
                anchors.centerIn: parent
                width: root.coverSize * 0.56
                height: root.coverSize * 0.56
                source: root.icon("na")
                sourceSize.width: root.coverSize * 0.56
                sourceSize.height: root.coverSize * 0.56
                visible: !root.showCover || player.artUrl.length === 0 || coverRoot.coverFailed
                opacity: 0.55
            }
        }
    }

    // 完整控制三件套：上一曲/播放暂停/下一曲（中、大尺寸共用）
    Component {
        id: controlsComponent

        Item {
            width: root.controlSize * 3 + root.controlSpacing * 2
            height: root.controlSize

            Row {
                anchors.centerIn: parent
                spacing: root.controlSpacing

                Item {
                    width: root.controlSize
                    height: root.controlSize
                    enabled: player.canGoPrevious
                    opacity: enabled ? 1.0 : 0.3

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.pressedControl === 0 ? root.pressFill
                            : (root.hoveredControl === 0 ? root.hoverFill : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Image {
                        anchors.fill: parent
                        source: root.icon("prev")
                        sourceSize.width: root.controlSize
                        sourceSize.height: root.controlSize
                    }
                }

                Item {
                    width: root.controlSize
                    height: root.controlSize
                    enabled: player.canControl && (player.canPlay || player.canPause)
                    opacity: enabled ? 1.0 : 0.3

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.pressedControl === 1 ? root.pressFill
                            : (root.hoveredControl === 1 ? root.hoverFill : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Image {
                        anchors.fill: parent
                        source: player.playbackStatus === "Playing"
                            ? root.icon("pause") : root.icon("play")
                        sourceSize.width: root.controlSize
                        sourceSize.height: root.controlSize
                    }
                }

                Item {
                    width: root.controlSize
                    height: root.controlSize
                    enabled: player.canGoNext
                    opacity: enabled ? 1.0 : 0.3

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.pressedControl === 2 ? root.pressFill
                            : (root.hoveredControl === 2 ? root.hoverFill : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Image {
                        anchors.fill: parent
                        source: root.icon("next")
                        sourceSize.width: root.controlSize
                        sourceSize.height: root.controlSize
                    }
                }
            }
        }
    }

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

        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: coverComponent
            active: root.showCover
            visible: root.showCover
            width: root.coverSize
            height: root.coverSize
        }

        Loader {
            id: mediumControls
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: controlsComponent
            active: root.showControls
            visible: root.showControls
            width: root.controlSize * 3 + root.controlSpacing * 2
            height: root.controlSize
        }
    }

    // 4×2 宽：保持左右布局（封面左，标题/艺术家/控件右上中下）
    RowLayout {
        anchors.fill: parent
        spacing: 12
        visible: root.hasMedia && root.wideCard

        Loader {
            sourceComponent: coverComponent
            active: root.showCover
            visible: root.showCover
            Layout.preferredWidth: root.coverSize
            Layout.preferredHeight: root.coverSize
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Text {
                Layout.fillWidth: true
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

            // 有界弹性空隙：控件贴底，但艺术家与控件之间不超过 gapLimit
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.maximumHeight: root.gapLimit
            }

            Loader {
                id: wideControls
                sourceComponent: controlsComponent
                active: root.showControls
                visible: root.showControls
                width: root.controlSize * 3 + root.controlSpacing * 2
                height: root.controlSize
            }

            // 底部兜底弹性空隙：保证控件行贴底
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
            }
        }
    }

    // 4×4 大：居中上下布局，封面/文字/控件全部水平居中
    Column {
        anchors.centerIn: parent
        spacing: root.verticalSpacing
        visible: root.hasMedia && root.large

        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: coverComponent
            active: root.showCover
            visible: root.showCover
            width: root.coverSize
            height: root.coverSize
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

        Loader {
            id: largeControls
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: controlsComponent
            active: root.showControls
            visible: root.showControls
            width: root.controlSize * 3 + root.controlSpacing * 2
            height: root.controlSize
        }
    }
}
