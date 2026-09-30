// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.widgettoolbar 1.0
import Qt5Compat.GraphicalEffects
import "../components" as Components

// 内置示例小组件：相框（默认 2×2）
// 相片满铺卡片本体（不走 WidgetCard 的内边距卡片底），相框边框由自身绘制。
//
// 数据层（经宿主 Network/FileIO 代理，全部落在实例工作目录内）：
//  - 工作目录 = dataDir/<instanceId>/；current.jpg 当前相片，
//    meta.json 记 {"mode","imageUrl","fetchedDate","dayOffset","blur"}；
//  - 五种来源：bingDaily（blur∈[1,50] 走模糊端点，否则图片流直达）、
//    bingHistory（/v1?d=N 或模糊端点）；两 Bing 模式主源下载失败均回退
//    官方 HPImageArchive JSON（bingDaily idx=0、bingHistory idx=回看天数）；
//    bingRandom（/v1/rand，同样两阶段自适应：先 JSON 试探挖直链，
//    json-parse 失败则视端点为图片流整段下载）、url（仅 https）、
//    local（无网络，取 image 设置值）；
//  - 缓存命中规则见 cacheHit()：meta 与当前配置一致且 current.jpg 存在
//    即直接显示；右键"刷新"是唯一强制重新取图通道；
//  - 请求去重：pendingJsonId/pendingDownloadId 只认最新 requestId，
//    旧回调一律丢弃，防止陈旧响应污染新状态。
Item {
    id: root

    // ===== 宿主注入（WidgetHostItem 以 Binding 写入，须先声明接住） =====
    property string instanceId: ""
    property string dataDir: ""
    property var widgetConfig: ({})
    property int hostCols: 0
    property int hostRows: 0
    // 相框无"卡片底"概念，透明模式对它无意义，仅声明以防注入报错
    property bool hostCardTransparent: false

    clip: true

    // ===== 配置解析（统一在此校验/钳制，脏配置回退默认值） =====
    readonly property string sourceMode: {
        var v = widgetConfig ? widgetConfig.sourceMode : null
        var modes = ["bingDaily", "bingRandom", "bingHistory", "url", "local"]
        for (var i = 0; i < modes.length; i++) {
            if (v === modes[i])
                return v
        }
        return "bingDaily"
    }
    readonly property int historyDaysAgo: {
        var v = widgetConfig ? Number(widgetConfig.historyDaysAgo) : NaN
        if (!isFinite(v))
            v = 1
        return Math.max(1, Math.min(7, Math.round(v)))
    }
    readonly property int bingBlur: {
        var v = widgetConfig ? Number(widgetConfig.bingBlur) : NaN
        if (!isFinite(v))
            v = 0
        return Math.max(0, Math.min(50, Math.round(v)))
    }
    // 1..50 才走模糊端点，其余（含越界钳回 0）视作不模糊
    readonly property int effectiveBlur: (root.bingBlur >= 1 && root.bingBlur <= 50)
        ? root.bingBlur : 0
    readonly property string customUrl: widgetConfig
        && typeof widgetConfig.customUrl === "string" ? widgetConfig.customUrl.trim() : ""
    readonly property string localImage: widgetConfig
        && typeof widgetConfig.localImage === "string" ? widgetConfig.localImage : ""
    readonly property string frameStyle: {
        var v = widgetConfig ? widgetConfig.frameStyle : null
        return (v === "none" || v === "solid" || v === "dashed") ? v : "solid"
    }
    readonly property color frameColor: Components.ColorUtils.resolveColor(
        widgetConfig ? widgetConfig.frameColor : null, "#FFFFFFFF")
    readonly property int frameWidth: {
        var v = widgetConfig ? Number(widgetConfig.frameWidth) : NaN
        if (!isFinite(v))
            v = 4
        return Math.max(0, Math.min(24, Math.round(v)))
    }
    readonly property int frameRadius: {
        var v = widgetConfig ? Number(widgetConfig.frameRadius) : NaN
        if (!isFinite(v))
            v = 8
        return Math.max(0, Math.min(32, Math.round(v)))
    }

    // ===== 相框几何 =====
    readonly property bool frameVisible: root.frameStyle !== "none"
    // 无边框 → 边框宽 0；实线/虚线 → 相片按边框宽度整体内缩
    readonly property real photoMargin: root.frameVisible ? root.frameWidth : 0
    // 外框圆角钳到卡片半宽/半高；相片圆角 = 外框圆角 − 边宽（贴边框内缘）
    readonly property real frameRadiusEff: Math.max(0, Math.min(
        root.frameRadius, root.width / 2, root.height / 2))
    readonly property real photoRadius: Math.max(0, root.frameRadiusEff - root.photoMargin)

    // ===== 数据层 =====
    readonly property string workDir: dataDir.length > 0 && instanceId.length > 0
        ? dataDir + "/" + instanceId : ""
    readonly property string currentPath: workDir.length > 0
        ? workDir + "/current.jpg" : ""
    readonly property string metaPath: workDir.length > 0
        ? workDir + "/meta.json" : ""

    // meta.json ↔ 对象（{"mode","imageUrl","fetchedDate","dayOffset","blur"}）
    property var meta: null
    // 进行中的请求 id：完成回调只认最新一次（-1 = 无在途请求）
    property int pendingJsonId: -1
    property int pendingDownloadId: -1
    // 在途请求的元信息：回调成功后据此写 meta.json
    property string jsonStage: ""            // "adaptive" | "officialFallback"
    property string pendingMode: ""
    property string pendingImageUrl: ""
    property string pendingFetchedDate: ""
    property int pendingDayOffset: 0
    property int pendingBlur: 0
    property string pendingEndpoint: ""
    // bingDaily 主源失败 → 官方 JSON 回退（仅回退一次）
    property bool bingFallback: false
    // UI 状态机：loading / ready / error / noImage（本地模式未选图）
    property string phase: "loading"
    property string errorCode: ""
    // 当前展示的相片绝对路径（赋值驱动，非绑定）
    property string photoPath: ""
    // file:// URL：整段编码后再还原 "/"，空格/# 等特殊字符的路径也能加载
    //（与宿主设置面板缩略图同法）
    readonly property string photoUrl: photoPath.length > 0
        ? "file://" + encodeURIComponent(photoPath).replace(/%2F/g, "/") : ""

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function readMeta() {
        if (root.metaPath.length === 0)
            return null
        var raw = FileIO.readTextFile(root.metaPath)
        if (raw.length === 0)
            return null
        try {
            var obj = JSON.parse(raw)
            return (obj && typeof obj === "object") ? obj : null
        } catch (e) {
            return null
        }
    }

    function writeMeta(mode, imageUrl, fetchedDate, dayOffset, blur) {
        if (root.metaPath.length === 0)
            return
        var obj = {
            "mode": mode,
            "imageUrl": imageUrl,
            "fetchedDate": fetchedDate,
            "dayOffset": dayOffset,
            "blur": blur
        }
        FileIO.writeTextFile(root.metaPath, JSON.stringify(obj))
    }

    function resetPending() {
        root.pendingJsonId = -1
        root.pendingDownloadId = -1
        root.jsonStage = ""
    }

    function showError(code) {
        root.resetPending()
        root.photoPath = ""
        root.phase = "error"
        root.errorCode = code.length > 0 ? code : "network"
    }

    // 缓存命中：meta 与当前配置一致且 current.jpg 存在（右键刷新绕过）
    function cacheHit(mode) {
        if (root.currentPath.length === 0 || !FileIO.exists(root.currentPath))
            return false
        if (!root.meta)
            return false
        if (mode === "bingDaily")
            return root.meta.mode === "bingDaily"
                && root.meta.fetchedDate === root.today()
                && Number(root.meta.blur) === root.effectiveBlur
        if (mode === "bingHistory")
            return root.meta.mode === "bingHistory"
                && Number(root.meta.dayOffset) === root.historyDaysAgo
                && Number(root.meta.blur) === root.effectiveBlur
        if (mode === "bingRandom")
            return root.meta.mode === "bingRandom"
        if (mode === "url")
            return root.meta.mode === "url" && root.meta.imageUrl === root.customUrl
        return false
    }

    // ===== 取图总入口：force=false 先判缓存，true 忽略缓存强制取图 =====
    function evaluate(force) {
        // instanceId/dataDir 注入未完成时等待 onWorkDirChanged 重入
        if (root.workDir.length === 0)
            return
        root.meta = root.readMeta()
        var mode = root.sourceMode

        // 本地模式：无网络，直接映射 image 设置值（dataDir + "/" + 相对路径）
        if (mode === "local") {
            root.resetPending()
            root.errorCode = ""
            if (root.localImage.length > 0) {
                root.photoPath = root.dataDir + "/" + root.localImage
                root.phase = "ready"
            } else {
                root.photoPath = ""
                root.phase = "noImage"
            }
            return
        }

        if (!force && root.cacheHit(mode)) {
            root.resetPending()
            root.errorCode = ""
            root.phase = "ready"
            root.showCurrent(false)
            return
        }

        if (mode === "url") {
            // 自定义网址必须以 https:// 开头，非法直接错误占位
            if (root.customUrl.length === 0
                    || root.customUrl.indexOf("https://") !== 0) {
                root.showError("invalid-url")
                return
            }
            root.startDownload(root.customUrl, "url", root.customUrl,
                               root.today(), 0, 0)
            return
        }
        if (mode === "bingDaily") {
            // blur∈[1,50] 走模糊端点（两阶段自适应，d=0 即今日），
            // 否则图片流直达
            root.bingFallback = false
            if (root.effectiveBlur > 0) {
                root.startAdaptive(
                    "https://api.bingimg.cn/v1/blur?d=0&w=1920&h=1080&r="
                        + root.effectiveBlur,
                    "bingDaily", 0, root.effectiveBlur)
            } else {
                root.startDownload("https://api.bingimg.cn/api/v1/image/bing-daily",
                                   "bingDaily",
                                   "https://api.bingimg.cn/api/v1/image/bing-daily",
                                   root.today(), 0, 0)
            }
            return
        }
        if (mode === "bingHistory") {
            var d = root.historyDaysAgo
            var endpoint = root.effectiveBlur > 0
                ? "https://api.bingimg.cn/v1/blur?d=" + d + "&w=1920&h=1080&r=" + root.effectiveBlur
                : "https://api.bingimg.cn/v1?d=" + d
            root.startAdaptive(endpoint, "bingHistory", d, root.effectiveBlur)
            return
        }
        if (mode === "bingRandom") {
            // bingBlur 忽略
            root.startAdaptive("https://api.bingimg.cn/v1/rand?w=1920&h=1080",
                               "bingRandom", 0, 0)
        }
    }

    // 两阶段自适应：先 JSON 试探（ttl=0 绕过宿主缓存，保随机/刷新语义），
    // 成功且 data 含 url 类字段 → 下载直链；json-parse 失败 → 端点本身是
    // 图片流，整段 download；其余错误 → 错误占位。
    function startAdaptive(endpoint, mode, dayOffset, blur) {
        root.bingFallback = false
        root.jsonStage = "adaptive"
        root.pendingMode = mode
        root.pendingEndpoint = endpoint
        root.pendingDayOffset = dayOffset
        root.pendingBlur = blur
        root.phase = "loading"
        root.pendingJsonId = Network.getJson(endpoint, 0)
    }

    function startDownload(url, mode, imageUrl, fetchedDate, dayOffset, blur) {
        if (url.length === 0 || root.currentPath.length === 0) {
            root.showError("invalid-url")
            return
        }
        root.jsonStage = ""
        root.pendingMode = mode
        root.pendingImageUrl = imageUrl
        root.pendingFetchedDate = fetchedDate
        root.pendingDayOffset = dayOffset
        root.pendingBlur = blur
        root.phase = "loading"
        root.pendingDownloadId = Network.download(url, root.currentPath)
    }

    // 从 JSON data 挖图片直链：官方回退取 images[0].url；
    // 自适应依次试 url / image / img / data.url（字符串且非空）
    function extractImageUrl(data) {
        if (!data)
            return ""
        if (root.jsonStage === "officialFallback") {
            var images = data.images
            if (images && images.length > 0 && images[0]
                    && typeof images[0].url === "string")
                return images[0].url
            return ""
        }
        if (typeof data.url === "string" && data.url.length > 0)
            return data.url
        if (typeof data.image === "string" && data.image.length > 0)
            return data.image
        if (typeof data.img === "string" && data.img.length > 0)
            return data.img
        if (data.data && typeof data.data.url === "string" && data.data.url.length > 0)
            return data.data.url
        return ""
    }

    // 展示 current.jpg；forceReload 用于刚下载落盘后强制 Image 重载
    //（同路径覆盖时 QML Image 不会因内容变化自动重读）
    function showCurrent(forceReload) {
        if (root.currentPath.length === 0)
            return
        if (forceReload)
            root.photoPath = ""
        root.photoPath = root.currentPath
    }

    // 唯一强制刷新通道：忽略缓存按当前模式重新取图
    //（download 原子覆盖 current.jpg，无需显式删除）
    function actionTriggered(actionId) {
        if (actionId === "refresh")
            root.evaluate(true)
    }

    // dataDir/instanceId 由宿主 Binding 注入，注入完成后首次评估
    onWorkDirChanged: Qt.callLater(function () { root.evaluate(false) })
    Component.onCompleted: {
        if (root.workDir.length > 0)
            root.evaluate(false)
    }
    // 配置面板保存后宿主刷新 widgetConfig → 重新评估缓存并按需取图
    onWidgetConfigChanged: root.evaluate(false)

    Connections {
        target: Network

        function onJsonFinished(requestId, success, data, errorCode, httpStatus) {
            if (requestId !== root.pendingJsonId)
                return
            root.pendingJsonId = -1
            if (!success) {
                // 自适应端点返回的不是 JSON：视为图片流，整段直接下载
                if (root.jsonStage === "adaptive" && errorCode === "json-parse") {
                    root.startDownload(root.pendingEndpoint, root.pendingMode,
                                       root.pendingEndpoint, root.today(),
                                       root.pendingDayOffset, root.pendingBlur)
                } else {
                    root.showError(errorCode)
                }
                return
            }
            var imageUrl = root.extractImageUrl(data)
            if (imageUrl.length === 0) {
                root.showError("json-parse")
                return
            }
            // 宿主 Network 仅接受 https：官方回退的相对路径拼 cn.bing.com
            // 前缀，明文 http 直链升 https（自定义网址仍严格要求 https）
            if (root.jsonStage === "officialFallback"
                    && imageUrl.indexOf("http") !== 0)
                imageUrl = "https://cn.bing.com" + imageUrl
            if (imageUrl.indexOf("http://") === 0)
                imageUrl = "https://" + imageUrl.slice(7)
            // 官方回退沿用触发回退时的 pendingMode（bingDaily/bingHistory），
            // meta 的 mode/dayOffset/blur 均按原始请求记录，缓存键才一致
            root.startDownload(imageUrl, root.pendingMode, imageUrl,
                               root.today(), root.pendingDayOffset,
                               root.pendingBlur)
        }

        function onDownloadFinished(requestId, success, destPath, errorCode, httpStatus) {
            if (requestId !== root.pendingDownloadId)
                return
            root.pendingDownloadId = -1
            if (success) {
                root.writeMeta(root.pendingMode, root.pendingImageUrl,
                               root.pendingFetchedDate, root.pendingDayOffset,
                               root.pendingBlur)
                root.meta = root.readMeta()
                root.errorCode = ""
                root.phase = "ready"
                root.showCurrent(true)
                return
            }
            // Bing 主源下载失败：回退官方 JSON（仅回退一次）——
            // bingDaily 取今日 idx=0；bingHistory 取回看日 idx=historyDaysAgo
            if (!root.bingFallback
                    && (root.pendingMode === "bingDaily"
                        || root.pendingMode === "bingHistory")) {
                root.bingFallback = true
                root.jsonStage = "officialFallback"
                root.phase = "loading"
                var idx = root.pendingMode === "bingHistory"
                    ? root.historyDaysAgo : 0
                root.pendingJsonId = Network.getJson(
                    "https://cn.bing.com/HPImageArchive.aspx?format=js&idx="
                        + idx + "&n=1",
                    600)
                return
            }
            root.showError(errorCode)
        }
    }

    // ===== 状态文案（qsTr 源串走宿主 lupdate 翻译流程） =====
    readonly property string statusText: {
        if (root.phase === "error") {
            var c = root.errorCode
            if (c.indexOf("http-") === 0)
                return qsTr("Service error")
            if (c === "timeout")
                return qsTr("Network timeout")
            if (c === "network")
                return qsTr("Network unavailable")
            if (c === "json-parse" || c === "too-large" || c === "path-denied"
                    || c === "scheme-not-https" || c === "invalid-url")
                return qsTr("Invalid response")
            return qsTr("Network unavailable")
        }
        return qsTr("Image unavailable")
    }
    // 占位图标尺寸随卡片缩放（钳 20..44），三档尺寸下均居中不溢出
    readonly property int placeholderIconSize: Math.max(20, Math.min(44,
        Math.round(Math.min(root.width, root.height) * 0.22)))
    readonly property int placeholderTextPixelSize: Math.max(10, Math.min(14,
        Math.round(Math.min(root.width, root.height) * 0.075)))

    // ===== UI 层 =====

    // 相片层：铺满卡片，按边框内缩，圆角经 OpacityMask 裁剪（CoverArt 同款）
    Image {
        id: photo
        anchors.fill: parent
        anchors.margins: root.photoMargin
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        smooth: true
        // 落盘文件自管缓存（重载由 showCurrent(true) 驱动）
        cache: false
        source: root.phase === "ready" ? root.photoUrl : ""
        visible: root.phase === "ready" && root.photoUrl.length > 0
        layer.enabled: root.photoRadius > 0 && visible
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: photo.width
                height: photo.height
                radius: Math.max(0, Math.min(root.photoRadius,
                                             photo.width / 2, photo.height / 2))
            }
        }
    }

    // 实线相框：Rectangle 边框画在自身 bounds 内，相片内缩 frameWidth 后
    // 恰好贴边框内缘；无边框时不绘制
    Rectangle {
        anchors.fill: parent
        visible: root.frameVisible
        color: "transparent"
        border.color: root.frameColor
        border.width: root.frameWidth
        radius: root.frameRadiusEff
    }

    // 虚线相框：Rectangle 不支持虚线，Canvas 自绘圆角虚线描边；
    // 路径整体内缩 frameWidth/2，让描边恰好占满边框厚度不越界
    Canvas {
        id: dashFrame
        anchors.fill: parent
        visible: root.frameStyle === "dashed"
        z: 1

        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // 边框属性变化均触发重绘
        Connections {
            target: root
            function onFrameColorChanged() { dashFrame.requestPaint() }
            function onFrameWidthChanged() { dashFrame.requestPaint() }
            function onFrameRadiusChanged() { dashFrame.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            if (!ctx)
                return
            ctx.reset()
            if (!root.frameVisible || root.frameWidth <= 0
                    || width <= 0 || height <= 0)
                return
            var inset = root.frameWidth / 2
            var left = inset
            var top = inset
            var right = width - inset
            var bottom = height - inset
            var r = Math.max(0, root.frameRadiusEff - inset)
            ctx.strokeStyle = root.frameColor
            ctx.lineWidth = root.frameWidth
            ctx.setLineDash([Math.max(4, root.frameWidth * 1.5),
                             Math.max(3, root.frameWidth)])
            ctx.beginPath()
            ctx.moveTo(left + r, top)
            ctx.lineTo(right - r, top)
            ctx.arc(right - r, top + r, r, -Math.PI / 2, 0)
            ctx.lineTo(right, bottom - r)
            ctx.arc(right - r, bottom - r, r, 0, Math.PI / 2)
            ctx.lineTo(left + r, bottom)
            ctx.arc(left + r, bottom - r, r, Math.PI / 2, Math.PI)
            ctx.lineTo(left, top + r)
            ctx.arc(left + r, top + r, r, Math.PI, Math.PI * 1.5)
            ctx.closePath()
            ctx.stroke()
        }
    }

    // 非就绪时的轻底色（错误/加载占位不与面板玻璃底糊成一片）
    Rectangle {
        anchors.fill: parent
        visible: root.phase !== "ready"
        radius: root.frameRadiusEff
        color: DTK.themeType === ApplicationHelper.DarkType
            ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    // 加载指示：网络取图中，或相片异步解码中
    BusyIndicator {
        anchors.centerIn: parent
        width: root.placeholderIconSize
        height: root.placeholderIconSize
        running: visible
        visible: root.phase === "loading"
            || (root.phase === "ready" && photo.status === Image.Loading)
    }

    // 错误 / 未选图占位：图标 + 本地化文案
    Column {
        anchors.centerIn: parent
        spacing: Math.max(4, Math.round(root.placeholderIconSize * 0.2))
        visible: (root.phase === "error")
            || (root.phase === "ready" && photo.status === Image.Error)
            || root.phase === "noImage"

        DciIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.phase === "noImage" ? "insert-image" : "dialog-warning"
            theme: DTK.themeType
            palette: DTK.makeIconPalette(root.palette)
            width: root.placeholderIconSize
            height: root.placeholderIconSize
            sourceSize.width: root.placeholderIconSize
            sourceSize.height: root.placeholderIconSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(0, root.width - 2 * root.photoMargin - 12)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            text: root.phase === "noImage"
                ? qsTr("Choose an image in settings") : root.statusText
            color: DTK.themeType === ApplicationHelper.DarkType
                ? "#e8e8e8" : "#1a1a1a"
            font.pixelSize: root.placeholderTextPixelSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.phase === "error" && root.errorCode.length > 0
            text: root.errorCode
            color: DTK.themeType === ApplicationHelper.DarkType
                ? "#b8b8b8" : "#6a6a6a"
            font.pixelSize: Math.max(9, root.placeholderTextPixelSize - 2)
        }
    }
}
