// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0
import org.deepin.ds 1.0

// 关于弹出面板（与添加小组件面板同框架）：
//  - 基于 PanelPopup（DPanel 辅助窗口）
//  - 产品名 / 开发团队 / 版本 / 许可证 / 仓库链接 / 团队官网
// 注意：文件名不使用 AboutDialog，避免与 org.deepin.dtk 导出的
// AboutDialog（Window 系组件，无 Popup open()）发生类型名冲突
PanelPopup {
    id: control

    // 弹在侧栏面板左侧，顶部对齐
    popupX: 0 - width - 8
    popupY: 0
    windowTitle: "dde-shell/widgettoolbar-about"

    width: 320
    height: 300

    Rectangle {
        id: contentCard
        anchors.fill: parent
        radius: DTK.platformTheme.windowRadius
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ===== 标题栏：标题 + 圆形叉号 =====
            PopupHeader {
                title: qsTr("About")
                onCloseRequested: control.close()
            }

            // ===== 产品信息 =====
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: "deepin小组件工具栏"
                font: DTK.fontManager.t5
                color: palette.windowText
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Developer team") + ": HuanSoft 浣软科技"
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.8
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Version") + ": 0.1.0.0"
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.8
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("License") + ": GPL-3.0-or-later"
                font: DTK.fontManager.t6
                color: palette.windowText
                opacity: 0.8
            }

            // ===== 链接 =====
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: qsTr("Repository") + ": "
                    + "<a href=\"https://github.com/HuanSoft-Open-Source-Community/deepin-widget-toolbar\">"
                    + "github.com/HuanSoft-Open-Source-Community/deepin-widget-toolbar</a>"
                font: DTK.fontManager.t6
                color: palette.link
                wrapMode: Text.Wrap
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Website") + ": "
                    + "<a href=\"https://huansoft.kxwl.ltd/\">huansoft.kxwl.ltd</a>"
                font: DTK.fontManager.t6
                color: palette.link
                wrapMode: Text.Wrap
                onLinkActivated: Qt.openUrlExternally(link)
            }
        }
    }
}
