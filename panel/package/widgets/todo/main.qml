// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import "../components" as Components

// 内置示例小组件：便签（默认 2×2）
// 实例数据持久化：XML 写入 dataDir/<instanceId>.xml（宿主隔离的实例数据目录），
// 首次加载时自动从旧版纯文本 <instanceId>.txt 迁移（.txt 保留作备份）。
//
// 待办模式（manifest 设置 todoMode，经 widgetConfig 实时生效）：
//  - 每个逻辑行行首缺省一个空心圆点，点击圆点在空心/实心间交替；
//  - 实心（完成）行：文字叠半透明底色"洗浅"（仅配色模式，见 washColor），
//    并由 strikeCanvas 画删除线；空心行不作任何处理；
//  - 内容区 Flickable + 全高 TextArea：可滚动页面高度随行数动态增长（无限滚动），
//    圆点/洗色/删除线与文字同处内容坐标系，随滚动整体移动。
//  圆点与行状态按"行索引"绑定：回车新增行缺省空心，上方插行后既有标记不随行迁移。
Components.WidgetCard {
    id: root

    widgetConfig: ({})
    dataDir: ""
    instanceId: ""

    property string xmlPath: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId + ".xml" : ""
    // 旧版纯文本存储：仅作迁移来源与损坏 XML 的回退，迁移后不再读取
    property string legacyNotePath: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId + ".txt" : ""
    transparentBackground: widgetConfig && widgetConfig.transparentBackground === true
    // 卡片底色跟随内容背景色，让内容自定义色延伸到整个便签卡片
    backgroundColor: root.contentBackgroundColor
    // 默认预设随明/暗主题切换（用户自定义颜色仍优先生效）
    textColor: Components.ColorUtils.themedColor(
        widgetConfig && widgetConfig.textColor, "#3d2b00", "#ede3be")
    property color titleBackgroundColor: Components.ColorUtils.themedColor(
        widgetConfig && widgetConfig.titleBackgroundColor, "#c8a500", "#6d5c05")
    property color titleTextColor: Components.ColorUtils.themedColor(
        widgetConfig && widgetConfig.titleTextColor, "#1a1a00", "#f4eecb")
    property color contentBackgroundColor: Components.ColorUtils.themedColor(
        widgetConfig && widgetConfig.contentBackgroundColor, "#fff8d6", "#2a2618")
    property color lineColor: Components.ColorUtils.themedColor(
        widgetConfig && widgetConfig.lineColor, "#cccccc", "#4a4636")
    // 待办模式开关（实例设置，缺省关闭）
    property bool todoMode: widgetConfig && widgetConfig.todoMode === true
    // 自动换行开关（实例设置，缺省开启）：开启时文字在卡片宽度内换行；
    // 关闭时按原样横向排布，超出部分由横向滚动查看（见 noteFlick.contentWidth）
    property bool autoWrap: !(widgetConfig && widgetConfig.autoWrap === false)
    // 各行完成标记（按行索引与文本行对齐；长度恒与 lineCount 同步）
    property var doneFlags: []
    // 程序化赋值文本期间置 true，抑制 onTextChanged 的标记同步
    property bool syncingFlags: false
    // 圆点/文字颜色：配色模式跟文字色，透明模式跟主题文字色（与正文一致）
    property color dotColor: root.effectiveTransparent ? root.themeTextColor : root.textColor
    // 完成行"洗浅"色：仅配色模式使用——把行洗向"内容底色"，浅底深字观感为变浅。
    // 透明模式不适用（该模式＝配色模式前样式，卡片底是主题雾底、无内部色块，
    // 与 lineCanvas 无行底线同理）：此处任何实色叠在半透雾底上都会糊出一条比文字
    // 更醒目的色带（回归现象），故透明模式整条不画，完成态由实心圆点 + 删除线表达。
    readonly property color washColor: Qt.rgba(root.contentBackgroundColor.r,
                                               root.contentBackgroundColor.g,
                                               root.contentBackgroundColor.b, 0.55)
    // 圆点列宽度（仅待办模式占位，文字整体右移让位）
    property int dotGutter: root.todoMode ? Math.max(18, Math.round(root.lineHeight * 0.85)) : 0
    property int dotSize: Math.max(9, Math.round(root.lineHeight * 0.36))
    property int titlePixelSize: Math.max(10, Math.min(20, Math.round(content.width * 0.04)))
    property real noteFontScale: {
        var mode = widgetConfig && widgetConfig.noteFontScale ? widgetConfig.noteFontScale : "medium"
        if (mode === "small")
            return 0.85
        if (mode === "large")
            return 1.2
        return 1.0
    }
    // 基准字号随卡片高度缩放，但钳制基准本身（9..17px）；档位缩放乘在基准上。
    // 旧实现把钳制施加在乘积上（min(20, h*0.09*scale)）：大卡片基准远超上限，
    // 小/中/大三档全部钳成同一字号、选项失效。改为钳基准后三档恒可辨，
    // 且 17×1.2≈20.4 与原 20px 上限观感一致。
    property int notePixelSize: Math.max(9, Math.round(
        Math.min(17, Math.max(9, content.height * 0.09)) * noteFontScale))

    // 滚动指示条活动态：任何 contentY 变化即点亮，闲置 900ms 后由 scrollActivity 熄灭
    property bool scrollActive: false
    // 行底线必须与 TextArea 实际文本行高一致，不能用像素大小的经验倍率估算
    property real lineHeight: Math.max(12, noteFontMetrics.lineSpacing)

    // ===== 实测行几何（对齐的事实源） =====
    // Controls 2 的 TextArea 是包装器，没有 lineHeight/lineHeightMode 属性可设，
    // 渲染行距无法与 i*lineSpacing 步进强制一致：QTextDocument 默认行高为
    // ascent+descent（不含 leading），CJK fallback 字体混排时还会被撑高，行数一多
    // 即累积偏移（圆点/格线与文字对不齐）。因此一切行几何改绑 positionToRectangle()
    // 实测值：lineStarts 为每行起始字符位（随文本变化重建，O(字符数) 一次 split）；
    // lineTops/lineHeights 为每行顶 y 与行高（y 值只取决于行号，同行编辑不改变任何
    // 行的几何，故仅在行数或字号变化时重测，击键高频路径零重测开销）。
    property var lineStarts: []
    property var lineTops: []
    property var lineHeights: []
    // 每个逻辑行占用的视觉行数（自动换行关闭时恒为 1）：圆点只画在逻辑行首，
    // 洗色/删除线/行底线按它向该逻辑行的每个视觉行展开（见 rebuildLineTops）
    property var lineRowCounts: []

    function rebuildLineStarts() {
        var lines = noteArea.text.replace(/\r\n/g, "\n").split("\n")
        var starts = []
        var pos = 0
        for (var i = 0; i < lines.length; i++) {
            starts.push(pos)
            pos += lines[i].length + 1
        }
        root.lineStarts = starts
    }

    function rebuildLineTops() {
        var tops = []
        var heights = []
        var rows = []
        for (var i = 0; i < root.lineStarts.length; i++) {
            var r = noteArea.positionToRectangle(root.lineStarts[i])
            tops.push(r.y)
            heights.push(r.height)
        }
        // 视觉行数：用相邻逻辑行顶距反推（= 行距 / 本行首行高），O(逻辑行数)、
        // 不逐字符扫描；末行改用行尾字符所在视觉行反推。未换行（含自动换行关闭）恒为 1。
        // 圆点只落在每个逻辑行首行，续行不再出点。
        for (var j = 0; j < tops.length; j++) {
            var count = 1
            var h = heights[j]
            if (h > 0) {
                if (j + 1 < tops.length) {
                    count = Math.max(1, Math.round((tops[j + 1] - tops[j]) / h))
                } else {
                    var start = root.lineStarts[j]
                    var len = noteArea.length - start
                    if (len > 0) {
                        var lastTop = noteArea.positionToRectangle(start + len - 1).y
                        count = Math.max(1, Math.round((lastTop - tops[j]) / h) + 1)
                    }
                }
            }
            rows.push(count)
        }
        // 先写行数与行高、最后写 lineTops（Repeater 的 model 即 lineTops.length）：
        // 委托创建时三个数组已一致，不会取到 undefined 几何
        root.lineRowCounts = rows
        root.lineHeights = heights
        root.lineTops = tops
        if (lineCanvas)
            lineCanvas.requestPaint()
        if (strikeCanvas)
            strikeCanvas.requestPaint()
        // 记录本次测量所用的几何键（见 rebuildLineTopsIfGeometryChanged）
        root.measuredWidth = noteArea.width
        root.measuredLeftPadding = noteArea.leftPadding
        root.measuredLines = root.lineStarts.length
        root.measuredAutoWrap = root.autoWrap
    }

    // 行几何重测的去抖入口：只有「会影响行 y/高」的输入变化才重测——noteArea 宽度、
    // 左内边距（待办模式下为圆点让位，切换待办模式或改字号都会变）与行数。
    // 三个键都没变就直接返回，因此把它挂在宽高/内边距的变更处理器上也不会给击键
    // 路径增加重测开销；卡片尺寸切换与待办模式开关此前完全不触发重测，圆点与
    // 删除线的 y 会滞后到下一次文本或字号变化才对齐。
    property real measuredWidth: -1
    property real measuredLeftPadding: -1
    property int measuredLines: -1
    property bool measuredAutoWrap: true
    function rebuildLineTopsIfGeometryChanged() {
        if (!noteArea)
            return
        // 自动换行关闭时每个逻辑行恒为一个视觉行，行几何与控件宽度无关，
        // 宽度键直接置为命中，避免横向内容增长时反复重测
        if ((!root.autoWrap || Math.abs(noteArea.width - measuredWidth) < 0.5)
                && Math.abs(noteArea.leftPadding - measuredLeftPadding) < 0.5
                && root.lineStarts.length === measuredLines
                && root.autoWrap === measuredAutoWrap)
            return
        rebuildLineTops()
    }

    // y（noteArea 内容坐标）→ 行号：取最后一个行顶 <= y 的行
    function lineIndexAt(y) {
        for (var i = root.lineTops.length - 1; i >= 0; i--) {
            if (y >= root.lineTops[i])
                return i
        }
        return -1
    }
    property int autoSaveInterval: widgetConfig && widgetConfig.autoSaveInterval
        ? Number(widgetConfig.autoSaveInterval) : 5000

    onNotePixelSizeChanged: {
        if (lineCanvas)
            lineCanvas.requestPaint()
        // 字号变化会重排所有行：延迟到布局更新后重测行几何
        Qt.callLater(root.rebuildLineTops)
    }
    onLineHeightChanged: {
        if (lineCanvas) lineCanvas.requestPaint()
        if (strikeCanvas) strikeCanvas.requestPaint()
    }
    onAutoWrapChanged: {
        // 关→开：横向位置对新布局无意义，复位到最左
        if (noteFlick)
            noteFlick.contentX = 0
        // 换行模式改变整块行几何（视觉行数随之变化）：延迟到布局更新后重测
        Qt.callLater(root.rebuildLineTops)
    }
    onTodoModeChanged: {
        // 切模式时文本不变、标记保留；对齐一次防越界
        root.syncFlags()
        if (strikeCanvas) strikeCanvas.requestPaint()
        if (lineCanvas) lineCanvas.requestPaint()
        // 待办模式会改 leftPadding（圆点让位），行几何需重测（键未变则内部直接返回）
        Qt.callLater(root.rebuildLineTopsIfGeometryChanged)
    }
    onDoneFlagsChanged: if (strikeCanvas) strikeCanvas.requestPaint()

    // dataDir/instanceId 由宿主 Binding 注入，xmlPath 就绪后加载/迁移一次
    onXmlPathChanged: {
        Qt.callLater(function () {
            if (noteArea)
                noteArea.loadNote()
        })
    }

    // ===== 行状态模型 =====

    function isDone(index) {
        return index >= 0 && index < root.doneFlags.length
            && root.doneFlags[index] === true
    }

    // 把标记数组对齐到当前**逻辑行**数（自动换行只增加视觉行，不改变标记口径）：
    // 截断多余、尾部补 false（新增行缺省空心）。
    // 已有标记按行索引保留。行数未变时不重建数组，避免每次击键触发
    // doneFlagsChanged 引发删除线画布整幅重绘。
    function syncFlags() {
        if (root.syncingFlags)
            return
        var n = root.lineStarts.length
        if (root.doneFlags.length === n)
            return
        var flags = root.doneFlags.slice(0, n)
        while (flags.length < n)
            flags.push(false)
        root.doneFlags = flags
    }

    // ===== 点击路由 =====

    // 主面板拖放层接收按下以持有鼠标抓取；普通点击由此转发，
    // 让便签仍能进入编辑并把光标放到点击位置。
    // 注意：X11 下面板是 Dock/Notification 类窗口，kwin 不因点击授予键盘
    // 焦点——只做 QML 取焦时光标会闪但按键到不了窗口。因此点击进入编辑
    // 时须随用户手势请求窗口激活（仅本组件点击触发，媒体按钮等普通点击
    // 不会借 handleHostClick 抢走其它应用的键盘焦点）。
    property point lastClickPos: Qt.point(0, 0)
    property string textAtClick: ""

    function focusNoteAt(x, y) {
        var p = noteArea.mapFromItem(root, x, y)
        noteArea.forceActiveFocus()
        var pos = noteArea.positionAt(p.x, p.y)
        noteArea.cursorPosition = Math.max(0, pos)
    }

    // 待办模式点击圆点列：命中即翻转该行完成态并落盘，返回是否已消费。
    // mapFromItem 自动计入 Flickable 滚动偏移，行号按行高换算。
    function tryToggleDot(x, y) {
        if (!root.todoMode)
            return false
        var p = noteArea.mapFromItem(root, x, y)
        if (p.x < 0 || p.x >= noteArea.leftPadding - 2)
            return false
        var idx = root.lineIndexAt(p.y)
        if (idx < 0 || idx >= root.lineStarts.length)
            return false
        var flags = root.doneFlags.slice()
        while (flags.length <= idx)
            flags.push(false)
        flags[idx] = !flags[idx]
        root.doneFlags = flags
        noteArea.saveNote()
        return true
    }

    function handleHostClick(x, y) {
        WidgetHost.activateWindow()
        if (root.tryToggleDot(x, y))
            return
        root.lastClickPos = Qt.point(x, y)
        root.textAtClick = noteArea.text
        focusNoteAt(x, y)
        // 窗口激活是异步的（X11 下 kwin 处理激活后才 FocusIn），期间窗口
        // 激活事件可能重置 QML 焦点；短暂重发取焦直到稳定（有界，3×150ms，
        // 用户一旦开始输入即停，不与按键抢光标）。
        focusRetry.left = 3
        focusRetry.restart()
    }

    // 光标移动后滚入可视区：全高 TextArea 无内滚，可视窗口由 contentY 决定。
    // 先停滚轮回弹动画，避免动画随后把 contentY 拉回旧目标。
    function ensureCursorVisible() {
        bounceAnim.stop()
        var r = noteArea.cursorRectangle
        var lineTop = r.y - noteArea.topPadding
        var margin = 4
        if (lineTop < noteFlick.contentY + margin) {
            noteFlick.contentY = Math.max(0, lineTop - margin)
        } else if (lineTop + root.lineHeight > noteFlick.contentY + noteFlick.height - margin) {
            noteFlick.contentY = Math.min(
                Math.max(0, noteFlick.contentHeight - noteFlick.height),
                lineTop + root.lineHeight - noteFlick.height + margin)
        }
        // 横向：自动换行关闭（内容超宽）时光标越界也平移 contentX
        if (noteFlick.contentWidth > noteFlick.width + 1) {
            bounceAnimX.stop()
            var maxX = Math.max(0, noteFlick.contentWidth - noteFlick.width)
            if (r.x < noteFlick.contentX + margin) {
                noteFlick.contentX = Math.max(0, r.x - margin)
            } else if (r.x + r.width > noteFlick.contentX + noteFlick.width - margin) {
                noteFlick.contentX = Math.min(maxX,
                    r.x + r.width - noteFlick.width + margin)
            }
        }
    }

    Timer {
        id: focusRetry
        interval: 150
        repeat: true
        property int left: 0
        onTriggered: {
            if (left <= 0) {
                stop()
                return
            }
            --left
            if (noteArea.text !== root.textAtClick) {
                stop()
                return
            }
            root.focusNoteAt(root.lastClickPos.x, root.lastClickPos.y)
        }
    }

    // 自动换行模式下的行几何去抖：同行编辑（未增减逻辑行）也可能改变视觉行数
    // （把某行输入到换行、删到不再换行），逻辑行数未变时不立即重测，短延时合并连续击键
    Timer {
        id: wrapGeometryTimer
        interval: 120
        repeat: false
        onTriggered: root.rebuildLineTops()
    }

    // ===== XML 持久化 =====

    // 实体转义（写入侧）：item 文本内不会出现裸 < > &，保证逐行严格可解析
    function escapeXml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // 实体解码（读取侧）：先解字符实体、最后解 &amp;，与转义顺序互逆
    function decodeXml(s) {
        return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }

    // 严格解析自产 XML 为 [{done, text}]；空便签（无 item）返回 []；
    // 结构意外（被手工改动/损坏）返回 null，由调用方回退迁移路径。
    function parseXmlItems(raw) {
        if (raw.indexOf("<sticky-note") < 0)
            return null
        if (raw.indexOf("<item") >= 0) {
            var matched = false
            var items = []
            var re = /<item done="(true|false)">([\s\S]*?)<\/item>/g
            var m
            while ((m = re.exec(raw)) !== null) {
                matched = true
                items.push({ "done": m[1] === "true", "text": root.decodeXml(m[2]) })
            }
            if (!matched)
                return null // 有 item 标签但无一合法：视为损坏
            return items
        }
        return []
    }

    function applyItems(items) {
        var lines = []
        var flags = []
        for (var i = 0; i < items.length; i++) {
            lines.push(items[i].text)
            flags.push(items[i].done === true)
        }
        root.syncingFlags = true
        noteArea.text = lines.join("\n")
        root.syncingFlags = false
        root.doneFlags = flags
    }

    // 标题区高度：透明模式为纯文字（配色模式前样式），无标题条占位
    property int titleBarHeight: root.effectiveTransparent
        ? root.titlePixelSize : root.titlePixelSize + 8

    Column {
        id: content
        anchors.fill: parent
        spacing: 4

        // 标题条：仅非透明模式显示
        Rectangle {
            id: titleBar
            width: parent.width
            height: root.titlePixelSize + 8
            radius: 4
            visible: !root.effectiveTransparent
            color: root.titleBackgroundColor

            Text {
                anchors.centerIn: parent
                text: qsTr("Sticky Note")
                font.pixelSize: root.titlePixelSize
                color: root.titleTextColor
            }
        }

        // 透明模式标题：配色模式前样式——无底色条，主题自适应文字
        Text {
            visible: root.effectiveTransparent
            text: qsTr("Sticky Note")
            font.pixelSize: root.titlePixelSize
            color: root.themeTextColor
        }

        Item {
            width: parent.width
            height: parent.height - root.titleBarHeight - content.spacing

            // 内容底色：仅非透明模式显示（固定于可视区，不随内容滚动）
            Rectangle {
                anchors.fill: parent
                radius: DTK.platformTheme.windowRadius
                visible: !root.effectiveTransparent
                color: root.contentBackgroundColor
            }

            // 无限滚动：TextArea 全高铺开内容，可视窗口由 Flickable 决定，
            // contentHeight 随行数动态增长；滚轮/触摸板滚动，光标移动自动跟随。
            // 自动换行关闭时文本横向排布，contentWidth 随最长行增长 → 左右也能滚。
            // （宿主拖放层为长按拖拽持有按下，触屏单指拖滚不生效，属桌面场景取舍。）
            Flickable {
                id: noteFlick
                anchors.fill: parent
                clip: true
                contentWidth: root.autoWrap ? width : Math.max(width, noteArea.width)
                contentHeight: Math.max(height, noteArea.height)

                // 滚动即点亮指示条：滚轮、回弹动画、光标自动滚入三条路径都经
                // contentY/contentX 赋值，天然全部驱动（attached ScrollBar 依赖的
                // moving 恒为 false、hover 又被宿主拖放层持有，故弃用改自绘指示条）
                onContentYChanged: {
                    root.scrollActive = true
                    scrollActivity.restart()
                }
                onContentXChanged: {
                    root.scrollActive = true
                    scrollActivity.restart()
                }

                // 滚轮接管：无条件消费滚轮事件——到头继续滚不再透传给面板网格；
                // 越界部分转为小幅 overshoot 并回弹，形成"拉紧回弹"的视觉缓冲。
                // 触摸板 pixelDelta 逐帧映射，鼠标滚轮按 3 行/格映射。
                WheelHandler {
                    id: noteWheel
                    target: null
                    onWheel: (ev) => {
                        ev.accepted = true
                        var step = root.lineHeight * 3
                        var dy = ev.pixelDelta.y !== 0
                            ? -ev.pixelDelta.y
                            : -ev.angleDelta.y / 120 * step
                        var dx = ev.pixelDelta.x !== 0
                            ? -ev.pixelDelta.x
                            : -ev.angleDelta.x / 120 * step
                        if (dx === 0 && dy === 0)
                            return
                        // 越界余量钳制在约 2 行，避免连续滚动把内容拉飞
                        var maxOver = root.lineHeight * 2
                        noteFlick.cancelFlick()
                        var maxC = Math.max(0, noteFlick.contentHeight - noteFlick.height)
                        // 纵向：内容不足以滚动时该轴不动（仍消费事件防穿透）
                        if (dy !== 0 && maxC > 0) {
                            var clampedY = Math.max(0, Math.min(maxC, noteFlick.contentY + dy))
                            bounceAnim.stop()
                            noteFlick.contentY = Math.max(-maxOver,
                                Math.min(maxC + maxOver, noteFlick.contentY + dy))
                            if (noteFlick.contentY !== clampedY) {
                                // 越界 → 回弹到最近边界（OutCubic 模拟橡皮筋回位）
                                bounceAnim.to = clampedY
                                bounceAnim.restart()
                            }
                        }
                        // 横向：仅自动换行关闭、横向内容确实超宽时才滚动
                        if (dx !== 0) {
                            var maxR = Math.max(0, noteFlick.contentWidth - noteFlick.width)
                            if (maxR > 0) {
                                var clampedX = Math.max(0,
                                    Math.min(maxR, noteFlick.contentX + dx))
                                bounceAnimX.stop()
                                noteFlick.contentX = Math.max(-maxOver,
                                    Math.min(maxR + maxOver, noteFlick.contentX + dx))
                                if (noteFlick.contentX !== clampedX) {
                                    bounceAnimX.to = clampedX
                                    bounceAnimX.restart()
                                }
                            }
                        }
                    }
                }
                NumberAnimation {
                    id: bounceAnim
                    target: noteFlick
                    property: "contentY"
                    duration: 280
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    id: bounceAnimX
                    target: noteFlick
                    property: "contentX"
                    duration: 280
                    easing.type: Easing.OutCubic
                }

                TextArea {
                    id: noteArea
                    // 自动换行：文字在可视宽度内换行，不产生横向溢出；
                    // 关闭换行：控件宽度按内容宽度（含左右 padding）撑开，由横向滚动查看
                    width: root.autoWrap ? noteFlick.width
                        : Math.max(noteFlick.width,
                                   noteArea.contentWidth + noteArea.leftPadding
                                       + noteArea.rightPadding)
                    // 全高：内容不足时撑满可视区（底线画满整卡），超出时随内容增长
                    height: Math.max(noteFlick.height, implicitHeight)
                    wrapMode: root.autoWrap ? TextEdit.Wrap : TextEdit.NoWrap
                    font.pixelSize: root.notePixelSize
                    color: root.effectiveTransparent ? root.themeTextColor : root.textColor
                    placeholderText: qsTr("Write something…")
                    // 待办模式文字右移为圆点让位；经典模式恢复样式默认 padding
                    Binding {
                        target: noteArea
                        property: "leftPadding"
                        when: root.todoMode
                        value: root.dotGutter + 4
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    // 卡片尺寸切换 / 待办内边距变化都会改行几何：去抖重测（键未变则返回）
                    onWidthChanged: Qt.callLater(root.rebuildLineTopsIfGeometryChanged)
                    onHeightChanged: Qt.callLater(root.rebuildLineTopsIfGeometryChanged)
                    onLeftPaddingChanged: Qt.callLater(root.rebuildLineTopsIfGeometryChanged)
                    FontMetrics {
                        id: noteFontMetrics
                        font: noteArea.font
                    }
                    background: Canvas {
                        id: lineCanvas
                        anchors.fill: parent

                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            if (!ctx)
                                return
                            // 透明模式为配色模式前样式：无行底线
                            if (root.effectiveTransparent)
                                return
                            ctx.reset()
                            ctx.strokeStyle = root.lineColor
                            ctx.globalAlpha = 0.7
                            ctx.lineWidth = 1

                            // 待办模式从圆点列右侧起笔，避免线穿过圆点下方；
                            // 经典模式保持原有 x=2 起点不变
                            var x0 = root.todoMode ? Math.max(2, noteArea.leftPadding) : 2
                            // 已有行：精确画在实测行底（对齐事实源）；自动换行下每个
                            // 逻辑行按其视觉行数逐行画底，包住整个换行块
                            for (var i = 0; i < root.lineTops.length; i++) {
                                var rows = Math.max(1, root.lineRowCounts[i])
                                for (var k = 1; k <= rows; k++) {
                                    var ly = root.lineTops[i] + root.lineHeights[i] * k - 1
                                    if (ly >= height - noteArea.bottomPadding)
                                        return
                                    ctx.beginPath()
                                    ctx.moveTo(x0, ly)
                                    ctx.lineTo(width - 4, ly)
                                    ctx.stroke()
                                }
                            }
                            // 行数不足整卡：从最后一个实测行的下一行起按其实测行高补满，
                            // 空白区格线仍延续便签纸观感，且偏移不从头累积
                            if (root.lineTops.length > 0) {
                                var lastIdx = root.lineTops.length - 1
                                var step = root.lineHeights[lastIdx]
                                var y = root.lineTops[lastIdx] + step
                                    * (Math.max(1, root.lineRowCounts[lastIdx]) + 1) - 1
                                while (y < height - noteArea.bottomPadding) {
                                    ctx.beginPath()
                                    ctx.moveTo(x0, y)
                                    ctx.lineTo(width - 4, y)
                                    ctx.stroke()
                                    y += step
                                }
                            } else {
                                var y0 = noteArea.topPadding + root.lineHeight - 1
                                while (y0 < height - noteArea.bottomPadding) {
                                    ctx.beginPath()
                                    ctx.moveTo(x0, y0)
                                    ctx.lineTo(width - 4, y0)
                                    ctx.stroke()
                                    y0 += root.lineHeight
                                }
                            }
                        }
                    }

                    // 完成行删除线：画在洗色矩形之上（z 更高），保证清晰可辨
                    Canvas {
                        id: strikeCanvas
                        anchors.top: parent.top
                        anchors.left: parent.left
                        width: noteArea.width
                        height: noteArea.height
                        z: 4
                        visible: root.todoMode

                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            if (!ctx)
                                return
                            ctx.reset()
                            if (!root.todoMode)
                                return
                            ctx.strokeStyle = root.dotColor
                            ctx.globalAlpha = 0.8
                            ctx.lineWidth = 1
                            for (var i = 0; i < root.lineTops.length; i++) {
                                if (!root.isDone(i))
                                    continue
                                // 自动换行下按视觉行逐行画删除线，整块换行行都被划到
                                var rows = Math.max(1, root.lineRowCounts[i])
                                for (var k = 0; k < rows; k++) {
                                    var y = root.lineTops[i]
                                        + root.lineHeights[i] * (k + 0.5)
                                    ctx.beginPath()
                                    ctx.moveTo(noteArea.leftPadding, y)
                                    ctx.lineTo(width - 4, y)
                                    ctx.stroke()
                                }
                            }
                        }
                    }

                    // 完成行"洗浅"矩形：半透明内容底色叠于文字上（z 高于 TextArea），
                    // 深字浅底两种配色下都呈现"变浅"观感。透明模式不叠（见 washColor：
                    // 雾底之上任何色块都会糊成突兀高亮带），完成态仍有实心点与删除线。
                    // 逐个逻辑行一块，高度覆盖该行全部视觉行
                    Repeater {
                        model: root.todoMode ? root.lineTops.length : 0
                        delegate: Rectangle {
                            required property int index
                            z: 2
                            x: 0
                            y: root.lineTops[index]
                            width: noteArea.width
                            height: root.lineHeights[index]
                                * Math.max(1, root.lineRowCounts[index])
                            color: root.washColor
                            visible: root.isDone(index) && !root.effectiveTransparent
                        }
                    }

                    // 行首圆点列：空心（边框圆环）/实心（填充圆盘），随内容滚动；
                    // 垂直居中于实测行几何，与文字逐行严格对齐。
                    // model 取逻辑行数（lineTops.length）：自动换行产生的续行不是行首，
                    // 不再画点
                    Repeater {
                        model: root.todoMode ? root.lineTops.length : 0
                        delegate: Item {
                            id: dotItem
                            required property int index
                            z: 3
                            x: 4
                            y: root.lineTops[index]
                                + (root.lineHeights[index] - root.dotSize) / 2
                            width: root.dotSize
                            height: root.dotSize

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: root.isDone(dotItem.index) ? root.dotColor : "transparent"
                                border.color: root.dotColor
                                border.width: Math.max(1, root.dotSize * 0.09)
                                opacity: root.isDone(dotItem.index) ? 0.9 : 0.7
                            }
                        }
                    }

                    // ===== 加载 / 保存（XML + 旧 .txt 迁移） =====

                    function loadNote() {
                        if (root.xmlPath.length === 0)
                            return
                        // 1) XML 为事实源：存在即解析
                        if (FileIO.exists(root.xmlPath)) {
                            var items = root.parseXmlItems(FileIO.readTextFile(root.xmlPath))
                            if (items !== null) {
                                root.applyItems(items)
                                return
                            }
                            // 损坏 XML：落入下方迁移/空路径，下次保存自然修复
                        }
                        // 2) 迁移：旧版纯文本 → 立即写 XML（.txt 保留作备份，此后不读）
                        if (FileIO.exists(root.legacyNotePath)) {
                            var legacy = FileIO.readTextFile(root.legacyNotePath)
                            root.syncingFlags = true
                            noteArea.text = legacy.replace(/\r\n/g, "\n")
                            root.syncingFlags = false
                            root.syncFlags()
                            noteArea.saveNote()
                            return
                        }
                        // 3) 全新实例
                        root.syncingFlags = true
                        noteArea.text = ""
                        root.syncingFlags = false
                        root.doneFlags = []
                    }

                    function saveNote() {
                        if (root.xmlPath.length === 0)
                            return
                        var lines = text.replace(/\r\n/g, "\n").split("\n")
                        var out = '<?xml version="1.0" encoding="UTF-8"?>\n'
                            + '<sticky-note version="1">\n'
                        for (var i = 0; i < lines.length; i++) {
                            out += '  <item done="'
                                + (root.isDone(i) ? "true" : "false") + '">'
                                + root.escapeXml(lines[i]) + '</item>\n'
                        }
                        out += '</sticky-note>\n'
                        FileIO.writeTextFile(root.xmlPath, out)
                    }

                    onTextChanged: {
                        // 先按新文本重建逻辑行起点，再让标记数组对齐逻辑行数
                        root.rebuildLineStarts()
                        root.syncFlags()
                        // 逻辑行数变化立即重测；行数不变时换行模式下行几何仍可能变
                        //（同一行输入到换行/删到不换行），去抖重测
                        if (root.lineStarts.length !== root.lineTops.length)
                            root.rebuildLineTops()
                        else if (root.autoWrap)
                            wrapGeometryTimer.restart()
                    }
                    Component.onCompleted: {
                        root.rebuildLineStarts()
                        root.rebuildLineTops()
                    }
                    onCursorPositionChanged: root.ensureCursorVisible()

                    onActiveFocusChanged: {
                        if (!activeFocus)
                            saveNote()
                    }
                    Component.onDestruction: saveNote()

                    Timer {
                        id: autoSaveTimer
                        interval: root.autoSaveInterval
                        repeat: true
                        running: noteArea.activeFocus
                        onTriggered: noteArea.saveNote()
                    }
                }
            }

            // ===== 滚动指示条：右缘细圆角拇指，随滚动点亮、闲置自动隐藏 =====
            // 纯视觉、无输入处理，不与宿主拖放层/滚轮路径竞争；
            // 颜色与圆点同源（dotColor），三种配色与透明模式均可见。
            // visible 只随"内容是否可滚"切换（低频、无动画语义）；点亮/熄灭全部
            // 走 opacity——若把 scrollActive 放进 visible，Qt 会在置 false 的瞬间
            // 硬切掉淡出动画（旧实现消退生硬的根因）。非对称时长 + OutCubic：
            // 出现 250ms 干脆、消退 600ms 从容，与卡片回弹（280ms OutCubic）
            // 及面板整体动效同族。
            Item {
                anchors.right: parent.right
                anchors.rightMargin: 3
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 4
                visible: noteFlick.contentHeight > noteFlick.height + 1
                opacity: root.scrollActive ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.scrollActive ? 250 : 600
                        easing.type: Easing.OutCubic
                    }
                }

                // 拇指：长度按可视占比（最小 24px），位置随 contentY 线性映射
                // （overshoot 越界值钳回可视范围，避免画到卡片外）。
                // y 上叠加轻阻尼（180ms OutCubic）：滚轮每格 3 行的离散跳步
                // 变为滑行，与回弹曲线同族、连续滚动时呈轻微跟随感。
                Rectangle {
                    width: parent.width
                    radius: width / 2
                    color: root.dotColor
                    opacity: 0.35
                    height: Math.max(24,
                        noteFlick.height * noteFlick.visibleArea.heightRatio)
                    Behavior on y {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    y: {
                        if (noteFlick.contentHeight <= noteFlick.height)
                            return 0
                        var span = noteFlick.contentHeight - noteFlick.height
                        var t = Math.max(0, Math.min(span, noteFlick.contentY)) / span
                        return t * (parent.height - height)
                    }
                }

                Timer {
                    id: scrollActivity
                    interval: 900
                    onTriggered: root.scrollActive = false
                }
            }

            // ===== 横向滚动指示条：自动换行关闭且内容超宽时的底部细条 =====
            // 与纵向指示条同一套"滚动点亮、闲置淡出"机制（共用 scrollActive 与
            // scrollActivity）；颜色与圆点同源，纯视觉、无输入处理。
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                height: 4
                visible: !root.autoWrap
                    && noteFlick.contentWidth > noteFlick.width + 1
                opacity: root.scrollActive ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.scrollActive ? 250 : 600
                        easing.type: Easing.OutCubic
                    }
                }

                // 拇指：长度按可视占比（最小 24px），位置随 contentX 线性映射
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    color: root.dotColor
                    opacity: 0.35
                    width: Math.max(24,
                        noteFlick.width * noteFlick.visibleArea.widthRatio)
                    Behavior on x {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    x: {
                        if (noteFlick.contentWidth <= noteFlick.width)
                            return 0
                        var span = noteFlick.contentWidth - noteFlick.width
                        var t = Math.max(0, Math.min(span, noteFlick.contentX)) / span
                        return t * (parent.width - width)
                    }
                }
            }
        }
    }
}
