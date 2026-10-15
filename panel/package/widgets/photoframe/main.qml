// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0
import org.deepin.ds 1.0
import org.deepin.widgettoolbar 1.0
import Qt5Compat.GraphicalEffects
import "../components" as Components

// 内置示例小组件：相框（默认 2×2）
// 相片满铺卡片本体（不走 WidgetCard 的内边距卡片底），相框边框由自身绘制。
//
// 数据层（经宿主 Network/FileIO 代理，全部落在实例工作目录内）：
//  - 工作目录 = dataDir/<instanceId>/；current.jpg 当前相片，
//    meta.json 记 {"mode","imageUrl","fetchedDate","dayOffset","blur"}；
//  - 五种来源：bingDaily、bingHistory（回看天数 1-7 随机）、bingRandom——
//    三个 Bing 模式的端点以图片流为主，整段 download 一次到位
//    （先 JSON 试探会撞宿主 1MB 响应上限，且同图下载两遍）；
//    但端点偶发返回 JSON 直链而非图片流，故下载完成后按内容分流——
//    探针解码确认是图片才写 meta/进 ready，JSON 挖直链二跳一次，
//    其余按"无效响应"报错（meta 只记可显示的图片，坏内容不进缓存）；
//    主源（api.bingimg.cn）下载失败回退官方 HPImageArchive JSON
//    （bingDaily idx=0、bingHistory idx=随机回看天、bingRandom 随机 idx∈[0,7]）；
//    url（仅 https）、local（无网络，取 image 设置值）；
//  - 缓存命中规则见 cacheHit()：meta 与当前配置一致且 current.jpg 存在
//    即直接显示；右键"刷新"是唯一强制重新取图通道；
//  - 请求去重：pendingJsonId/pendingDownloadId 只认最新 requestId，
//    旧回调一律丢弃；探针用 probeGeneration/activeProbeGen 代际校验，
//    陈旧探针结果同样丢弃，防止频繁刷新时卡在 loading。
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
    readonly property string customUrl: widgetConfig
        && typeof widgetConfig.customUrl === "string" ? widgetConfig.customUrl.trim() : ""
    readonly property string localImage: widgetConfig
        && typeof widgetConfig.localImage === "string" ? widgetConfig.localImage : ""
    readonly property string frameStyle: {
        var v = widgetConfig ? widgetConfig.frameStyle : null
        var styles = ["none", "solid", "dashed", "dotted", "dashDot",
                      "double", "dashLong", "dotDense"]
        for (var i = 0; i < styles.length; i++) {
            if (v === styles[i])
                return v
        }
        return "solid"
    }
    // 默认预设随明/暗主题切换（用户自定义颜色仍优先生效）
    readonly property color frameColor: Components.ColorUtils.themedColor(
        widgetConfig ? widgetConfig.frameColor : null, "#FFFFFFFF", "#FF2B2B2B")
    readonly property int frameWidth: {
        var v = widgetConfig ? Number(widgetConfig.frameWidth) : NaN
        if (!isFinite(v))
            v = 4
        return Math.max(0, Math.min(24, Math.round(v)))
    }
    readonly property int dashGap: {
        var v = widgetConfig ? Number(widgetConfig.dashGap) : NaN
        if (!isFinite(v))
            v = 4
        return Math.max(0, Math.min(24, Math.round(v)))
    }
    readonly property int dashLen: {
        var v = widgetConfig ? Number(widgetConfig.dashLen) : NaN
        if (!isFinite(v))
            v = 0
        return Math.max(0, Math.min(24, Math.round(v)))
    }

    // ===== 相框几何 =====
    readonly property bool frameVisible: root.frameStyle !== "none"
    // 无边框 → 边框宽 0；其余线型 → 相片按边框宽度整体内缩
    readonly property real photoMargin: root.frameVisible ? root.frameWidth : 0
    // 圆角取自系统窗口圆角（与系统体验统一），钳到卡片半宽/半高；
    // 相片圆角 = 外框圆角 − 边宽（贴边框内缘）
    readonly property real frameRadiusEff: Math.max(0, Math.min(
        DTK.platformTheme.windowRadius, root.width / 2, root.height / 2))
    readonly property real photoRadius: Math.max(0, root.frameRadiusEff - root.photoMargin)

    // 各线型 → 描边图案（双滑块模型：间距 dashGap 与点划长度 dashLen，均 0..24）。
    //   - dashGap：基准缝宽（视觉间隙像素）。各线型叠加固有偏移保持相对疏密可辨：
    //     dashed +0 / dashLong +0.8 / dotted −0.8 / dashDot −3.2 / dotDense −4，
    //     结果触底截断为 0（归零粘连成近实线属用户自选）；
    //   - dashLen：单段笔画的附加加长量，点段与线段共用——叠加在宽度线性基线
    //     （1.5u/2.5u/3.5u、点 0.1）之上，不破坏"段随宽度加粗加长"的本性，
    //     调大后点由正圆变胶囊；
    //   - round 帽（dotted/dotDense/dashDot）线帽在每段两端各外延 u/2，会吃掉
    //     间隔，gap 参数 = 缝宽 + u 补偿，使 dashGap 直接读作视觉缝宽；
    //     butt 帽（dashed/dashLong）不外延，gap 参数 = 缝宽。
    // 默认值（gap=4、len=0）与纯自动模型版在任意宽度下逐像素一致（硬锚点）。
    function dashPattern(style, w, gap, len) {
        var u = Math.max(1, w)
        var dl = len > 0 ? len : 0
        var dot = 0.1 + dl
        if (style === "dotted")
            return { "dash": [dot, u + Math.max(0, gap - 0.8)], "cap": "round" }
        if (style === "dotDense")
            return { "dash": [dot, u + Math.max(0, gap - 4)], "cap": "round" }
        if (style === "dashDot")
            return { "dash": [u * 2.5 + dl, u + Math.max(0, gap - 3.2),
                              dot, u + Math.max(0, gap - 3.2)], "cap": "round" }
        if (style === "dashLong")
            return { "dash": [u * 3.5 + dl, Math.max(0, gap + 0.8)], "cap": "butt" }
        // dashed（默认虚线）
        return { "dash": [u * 1.5 + dl, Math.max(0, gap)], "cap": "butt" }
    }

    // 圆角矩形描边路径：优先 ctx.roundRect()，不可用时退化为仅含 arc() 的
    // 标准路径（moveTo 到弧起点后连续 arc，四角不穿插 lineTo，避免重复连线错切）
    function roundRectPath(ctx, x, y, w, h, r) {
        var rr = Math.max(0, Math.min(r, w / 2, h / 2))
        ctx.beginPath()
        if (typeof ctx.roundRect === "function") {
            ctx.roundRect(x, y, w, h, rr)
            return
        }
        if (rr < 0.5) {
            ctx.moveTo(x, y)
            ctx.lineTo(x + w, y)
            ctx.lineTo(x + w, y + h)
            ctx.lineTo(x, y + h)
            ctx.closePath()
            return
        }
        ctx.moveTo(x + rr, y)
        ctx.arc(x + w - rr, y + rr, rr, -Math.PI / 2, 0)
        ctx.arc(x + w - rr, y + h - rr, rr, 0, Math.PI / 2)
        ctx.arc(x + rr, y + h - rr, rr, Math.PI / 2, Math.PI)
        ctx.arc(x + rr, y + rr, rr, Math.PI, Math.PI * 1.5)
        ctx.closePath()
    }

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
    property string jsonStage: ""            // "" | "officialFallback"
    property string pendingMode: ""
    property string pendingImageUrl: ""
    property string pendingFetchedDate: ""
    property int pendingDayOffset: 0
    // bingHistory 近三次回看天数，用于避免连续取到相同的"往日"图；
    // 仅内存态，widget 重建即清空
    property var recentDayOffsets: []
    property int pendingBlur: 0
    // bingDaily/bingHistory 主源失败 → 官方 JSON 回退（仅回退一次）
    property bool bingFallback: false
    // 每轮取图的防线（evaluate() 开头重置）：JSON 直链二跳最多一次、
    // 坏图自愈最多一次，防止失败后反复重试成环
    property bool sniffHopped: false
    property bool healedOnce: false
    // 隐藏探针解码校验进行中：photo 本体解码失败处理据此区分探针流程，
    // 并与 pendingJsonId/pendingDownloadId 同理丢弃陈旧校验结果
    property bool probing: false
    // 探针代际：每次 startProbe 递增，探针 onStatusChanged 仅处理当代际结果；
    // evaluate/startDownload 递增代际使在途探针结果作废（替代单纯 probing=false），
    // 杜绝频繁刷新时陈旧探针误触发 sniffDirectLink 或写 meta 导致卡在 loading
    property int probeGeneration: 0
    // 当前活跃探针的代际锁：startProbe 锁定为 probeGeneration，
    // onStatusChanged 仅在 activeProbeGen === probeGeneration 时处理；
    // source="" 阶段临时置 -1 以丢弃清空触发的状态变更
    property int activeProbeGen: -1
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

    // 调试日志：仅在 Panel.debugMode 开启时输出到 stderr（与 applauncher 同法）；
    // 用于追踪取图状态机，排查连续刷新卡 loading / 超时问题。
    // 用 typeof 守卫确保即使 Panel 上下文不可用也不抛异常中断主流程
    function dbg(msg) {
        try {
            if (typeof Panel !== "undefined" && Panel.debugMode)
                console.warn("[photoframe]", msg)
        } catch (e) {}
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
        root.dbg("showError code=" + code + " (was phase=" + root.phase + ")")
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
        if (mode === "bingHistory")
            return root.meta.mode === "bingHistory"
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
        root.dbg("evaluate force=" + force + " mode=" + root.sourceMode
                 + " phase=" + root.phase
                 + " pendingDl=" + root.pendingDownloadId
                 + " pendingJson=" + root.pendingJsonId)
        // 新一轮取图重置防线：二跳/自愈每轮各至多一次；同时作废在途探针，
        // 防止陈旧校验结果污染新状态（与 pendingId 去重同理）
        root.sniffHopped = false
        root.healedOnce = false
        root.probing = false
        root.probeGeneration++   // 作废在途探针，旧 onStatusChanged 结果被丢弃
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
            // 模糊端点已移除，统一走图片流端点；下载失败回退官方 HPImageArchive
            root.bingFallback = false
            root.startDownload("https://api.bingimg.cn/api/v1/image/bing-daily",
                               "bingDaily",
                               "https://api.bingimg.cn/api/v1/image/bing-daily",
                               root.today(), 0, 0)
            return
        }
        if (mode === "bingHistory") {
            // 回看天数在 1-7 之间随机，且近三次取值不重复：
            // 从 1-7 中剔除 recentDayOffsets 已有的值，在剩余池中随机抽取
            var recent = root.recentDayOffsets
            var pool = []
            for (var i = 1; i <= 7; i++) {
                if (recent.indexOf(i) < 0)
                    pool.push(i)
            }
            var d = pool[Math.floor(Math.random() * pool.length)]
            // 推入新值，保持最多近三次
            var next = recent.slice()
            next.push(d)
            while (next.length > 3)
                next.shift()
            root.recentDayOffsets = next
            root.bingFallback = false
            root.startDownload("https://api.bingimg.cn/v1?d=" + d,
                               "bingHistory",
                               "https://api.bingimg.cn/v1?d=" + d,
                               root.today(), d, 0)
            return
        }
        if (mode === "bingRandom") {
            // 端点本身即图片流，整段 download 直达；失败回退官方 HPImageArchive
            // （随机 idx 0-7），由 onDownloadFinished 触发
            root.bingFallback = false
            root.startDownload("https://api.bingimg.cn/v1/rand?w=1920&h=1080",
                               "bingRandom",
                               "https://api.bingimg.cn/v1/rand?w=1920&h=1080",
                               root.today(), 0, 0)
        }
    }

    function startDownload(url, mode, imageUrl, fetchedDate, dayOffset, blur) {
        if (url.length === 0 || root.currentPath.length === 0) {
            root.showError("invalid-url")
            return
        }
        root.dbg("startDownload mode=" + mode
                 + " cancelDl=" + root.pendingDownloadId
                 + " cancelJson=" + root.pendingJsonId
                 + " url=" + url.slice(0, 60))
        // 新一轮下载作废在途探针（含 JSON 分流二跳），防陈旧校验写坏 meta；
        // 同时作废在途 JSON 回退请求（pendingJsonId=-1），避免刷新时陈旧 JSON
        // 回调匹配旧 id 后用空 jsonStage 下载相对路径直链导致无效 URL 错误；
        // 取消上一个在途下载（pendingDownloadId）释放 NAM 连接槽，防连续刷新
        // 时陈旧请求堆积导致最新请求排队等待
        if (root.pendingDownloadId >= 0)
            Network.cancel(root.pendingDownloadId)
        if (root.pendingJsonId >= 0)
            Network.cancel(root.pendingJsonId)
        root.probing = false
        root.probeGeneration++   // 作废在途探针
        root.jsonStage = ""
        root.pendingJsonId = -1
        root.pendingMode = mode
        root.pendingImageUrl = imageUrl
        root.pendingFetchedDate = fetchedDate
        root.pendingDayOffset = dayOffset
        root.pendingBlur = blur
        root.phase = "loading"
        root.pendingDownloadId = Network.download(url, root.currentPath)
    }

    // 从官方回退 JSON data 挖图片直链：取 images[0].url
    function extractImageUrl(data) {
        if (!data)
            return ""
        var images = data.images
        if (images && images.length > 0 && images[0]
                && typeof images[0].url === "string")
            return images[0].url
        return ""
    }

    // 从下载内容的 JSON 里挖图片直链（端点常以 JSON 直链代替图片流）：
    // 依次兼容 images[0].url（HPImageArchive 格式，相对路径拼 cn.bing.com）、
    // url/image/img/data.url（须为字符串）；明文 http 升 https——
    // 宿主 Network 仅接受 https，与 onJsonFinished 的官方回退同法
    function extractSniffImageUrl(obj) {
        if (!obj || typeof obj !== "object")
            return ""
        var u = root.extractImageUrl(obj)
        if (u.length === 0) {
            var cands = [obj.url, obj.image, obj.img,
                         (obj.data && typeof obj.data === "object") ? obj.data.url : ""]
            for (var i = 0; i < cands.length; i++) {
                if (typeof cands[i] === "string" && cands[i].length > 0) {
                    u = cands[i]
                    break
                }
            }
        }
        if (u.length === 0)
            return ""
        if (u.indexOf("http://") === 0)
            u = "https://" + u.slice(7)
        else if (u.indexOf("http") !== 0)
            u = "https://cn.bing.com" + u
        return u
    }

    // 探针判定下载内容不是图片：按 JSON 读回文本挖直链二跳下载一次
    //（sniffHopped 保证每轮至多二跳防循环；pendingImageUrl 保持原请求键
    // 不改成直链——url 模式缓存键 meta.imageUrl 必须等于 customUrl）；
    // 挖不到直链或二跳已用 → "无效响应"错误占位，不写 meta 不污染缓存
    function sniffDirectLink() {
        var link = ""
        try {
            var raw = root.currentPath.length > 0
                ? FileIO.readTextFile(root.currentPath) : ""
            if (raw.length > 0)
                link = root.extractSniffImageUrl(JSON.parse(raw))
        } catch (e) {
            link = ""
        }
        if (link.length > 0 && !root.sniffHopped) {
            root.sniffHopped = true
            root.startDownload(link, root.pendingMode, root.pendingImageUrl,
                               root.pendingFetchedDate, root.pendingDayOffset,
                               root.pendingBlur)
            return
        }
        root.showError("json-parse")
    }

    // 展示 current.jpg；forceReload 用于刚下载落盘后强制 Image 重载
    //（同路径覆盖时 QML Image 不会因内容变化自动重读）；
    // forceReload=true 时先置空再用 Qt.callLater 延迟赋值，确保 photo 的
    // source 绑定观察到 "" → 文件路径的完整变化（避免属性变更合并导致
    // 中间值 "" 丢失，photo 卡在 Image.Loading 不重载）
    function showCurrent(forceReload) {
        if (root.currentPath.length === 0)
            return
        root.dbg("showCurrent force=" + forceReload
                 + " photoStatus=" + photo.status)
        if (forceReload) {
            root.photoPath = ""
            Qt.callLater(function () { root.photoPath = root.currentPath })
        } else {
            root.photoPath = root.currentPath
        }
    }

    // 下载成功 ≠ 有效图片：先经隐藏探针廉价解码确认 current.jpg 是真图片，
    // 确认通过才写 meta/进 ready，坏内容永不进 meta（防坏缓存持久驻留）
    function startProbe() {
        if (root.currentPath.length === 0) {
            root.showError("json-parse")
            return
        }
        root.dbg("startProbe gen=" + root.probeGeneration)
        root.probing = true
        // 先把代际锁置为 -1，让 source="" 触发的状态变更被代际校验丢弃；
        // 再递增 probeGeneration 并锁定 activeProbeGen，确保只有本次探针的
        // onStatusChanged 能通过代际校验（evaluate/startDownload 递增
        // probeGeneration 使旧探针结果作废）
        root.activeProbeGen = -1
        probe.source = ""
        root.probeGeneration++
        root.activeProbeGen = root.probeGeneration
        // 同路径覆盖后 Image 不自动重读：先清空再赋值强制重载（showCurrent 同法）；
        // file:// 编码构造与 photoUrl 同法，带特殊字符的路径也能加载
        probe.source = "file://" + encodeURIComponent(root.currentPath)
            .replace(/%2F/g, "/")
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
            root.dbg("onJsonFinished req=" + requestId
                     + " pending=" + root.pendingJsonId
                     + " success=" + success
                     + " err=" + errorCode
                     + " http=" + httpStatus)
            if (requestId !== root.pendingJsonId)
                return
            root.pendingJsonId = -1
            if (!success) {
                // 官方回退 JSON 失败：直接错误占位（仅回退一次，不再重试）
                root.showError(errorCode)
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
            // 官方回退沿用触发回退时的 pendingMode（bingDaily/bingHistory/bingRandom），
            // meta 的 mode/dayOffset/blur 均按原始请求记录，缓存键才一致
            root.startDownload(imageUrl, root.pendingMode, imageUrl,
                               root.today(), root.pendingDayOffset,
                               root.pendingBlur)
        }

        function onDownloadFinished(requestId, success, destPath, errorCode, httpStatus) {
            root.dbg("onDownloadFinished req=" + requestId
                     + " pending=" + root.pendingDownloadId
                     + " success=" + success
                     + " err=" + errorCode
                     + " http=" + httpStatus)
            if (requestId !== root.pendingDownloadId)
                return
            root.pendingDownloadId = -1
            if (success) {
                // 下载成功先"待确认"：保持 loading 与旧图，经探针解码确认
                // 是图片后才写 meta/进 ready（端点常返回 JSON 直链而非图片流，
                // 直写 meta 会把坏图当缓存命中持久驻留）
                root.startProbe()
                return
            }
            // Bing 主源下载失败：回退官方 JSON（仅回退一次）——
            // bingDaily 取今日 idx=0；bingHistory 取回看日 idx=pendingDayOffset；
            // bingRandom 随机 idx∈[0,7]
            if (!root.bingFallback
                    && (root.pendingMode === "bingDaily"
                        || root.pendingMode === "bingHistory"
                        || root.pendingMode === "bingRandom")) {
                root.bingFallback = true
                root.jsonStage = "officialFallback"
                root.phase = "loading"
                var idx
                if (root.pendingMode === "bingDaily")
                    idx = 0
                else if (root.pendingMode === "bingHistory")
                    idx = root.pendingDayOffset
                else
                    idx = Math.floor(Math.random() * 8)
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
        // 强制刷新的 loading 阶段旧图继续显示：新图落盘后 showCurrent(true)
        // 替换，下载失败才进错误占位（showError 会清空 photoPath）
        source: (root.phase === "ready" || root.phase === "loading")
            ? root.photoUrl : ""
        visible: (root.phase === "ready" || root.phase === "loading")
            && root.photoUrl.length > 0
        // 本体解码失败（缓存命中/本地路径坏图；探针流程由 probe 负责校验，
        // phase 停留 loading 不会误入）：网络模式强制重取一次自愈，再失败
        // 错误占位；本地模式不强制重取、不改 phase，保留"图片不可用"占位
        onStatusChanged: {
            root.dbg("photo status=" + status
                     + " phase=" + root.phase
                     + " probing=" + root.probing)
            if (status !== Image.Error || root.probing || root.phase !== "ready")
                return
            if (root.sourceMode === "local")
                return
            if (!root.healedOnce) {
                root.healedOnce = true
                root.evaluate(true)
                return
            }
            root.showError("json-parse")
        }
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

    // 隐藏解码探针：current.jpg 落盘后先经它廉价解码（sourceSize 32×32、
    // 同步加载）确认是真图片，解码确认通过才写 meta/进 ready；
    // cache:false 防同路径旧解码结果被 QML 图片缓存顶替而误判
    Image {
        id: probe
        visible: false
        asynchronous: false
        cache: false
        sourceSize.width: 32
        sourceSize.height: 32

        onStatusChanged: {
            // 代际校验：只有当前活跃探针（activeProbeGen === probeGeneration）
            // 的结果才处理；evaluate/startDownload 递增 probeGeneration 使陈旧
            // 探针结果（含 source="" 触发的 Null/Error）一律丢弃，杜绝频繁
            // 刷新时陈旧探针误触发 sniffDirectLink 或写 meta 导致卡在 loading
            if (root.activeProbeGen !== root.probeGeneration) {
                root.dbg("probe stale status=" + status
                         + " activeGen=" + root.activeProbeGen
                         + " gen=" + root.probeGeneration)
                return
            }
            if (!root.probing)
                return
            root.dbg("probe status=" + status + " gen=" + root.probeGeneration)
            if (status === Image.Ready) {
                root.probing = false
                // 解码确认通过：此刻才写 meta，坏内容永不进缓存
                root.writeMeta(root.pendingMode, root.pendingImageUrl,
                               root.pendingFetchedDate, root.pendingDayOffset,
                               root.pendingBlur)
                root.meta = root.readMeta()
                root.errorCode = ""
                root.phase = "ready"
                root.showCurrent(true)
            } else if (status === Image.Error) {
                root.probing = false
                // 不是图片：走 JSON 分流挖直链二跳，挖不到按"无效响应"报错
                root.sniffDirectLink()
            }
        }
    }

    // 实线相框：Rectangle 边框画在自身 bounds 内，相片内缩 frameWidth 后
    // 恰好贴边框内缘；仅 solid 绘制（其余线型交给 Canvas，避免实线盖住虚线）
    Rectangle {
        anchors.fill: parent
        visible: root.frameStyle === "solid"
        color: "transparent"
        border.color: root.frameColor
        border.width: root.frameWidth
        radius: root.frameRadiusEff
    }

    // 虚线/点线/点划线/双线相框：Rectangle 不支持 lineDash，Canvas 自绘圆角
    // 描边；路径整体内缩 frameWidth/2，让描边恰好占满边框厚度不越界
    Canvas {
        id: dashFrame
        anchors.fill: parent
        visible: root.frameVisible && root.frameStyle !== "solid"
        z: 1

        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // 边框属性变化均触发重绘（圆角跟随系统窗口圆角）
        Connections {
            target: root
            function onFrameColorChanged() { dashFrame.requestPaint() }
            function onFrameWidthChanged() { dashFrame.requestPaint() }
            function onFrameStyleChanged() { dashFrame.requestPaint() }
            function onFrameRadiusEffChanged() { dashFrame.requestPaint() }
            function onDashGapChanged() { dashFrame.requestPaint() }
            function onDashLenChanged() { dashFrame.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            if (!ctx)
                return
            ctx.reset()
            // reset() 不重置 lineDash：每帧显式清空，避免上一帧图案残留
            ctx.setLineDash([])
            if (!root.frameVisible || root.frameStyle === "solid"
                    || root.frameWidth <= 0 || width <= 0 || height <= 0)
                return
            ctx.strokeStyle = root.frameColor
            ctx.lineJoin = "round"

            // 双线：两条同心细线，各占边框厚度 1/3，分别贴内外缘
            if (root.frameStyle === "double") {
                var lw = Math.max(1, root.frameWidth / 3)
                var offs = [root.frameWidth / 6, root.frameWidth * 5 / 6]
                ctx.lineWidth = lw
                ctx.lineCap = "butt"
                for (var i = 0; i < offs.length; i++) {
                    var o = offs[i]
                    root.roundRectPath(ctx, o, o, width - 2 * o, height - 2 * o,
                                       root.frameRadiusEff - o)
                    ctx.stroke()
                }
                return
            }

            var pat = root.dashPattern(root.frameStyle, root.frameWidth, root.dashGap, root.dashLen)
            var inset = root.frameWidth / 2
            ctx.lineWidth = root.frameWidth
            ctx.lineCap = pat.cap
            ctx.setLineDash(pat.dash)
            root.roundRectPath(ctx, inset, inset, width - 2 * inset,
                               height - 2 * inset, root.frameRadiusEff - inset)
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

    // loading 安全超时：取图流程异常（请求队列阻塞/回调丢失）时兜底退出转圈，
    // 进入错误占位；phase 离开 loading 时 Timer 自动停止
    Timer {
        id: loadingSafetyTimer
        interval: 12000
        repeat: false
        running: root.phase === "loading"
        onTriggered: {
            root.dbg("loadingSafetyTimer TIMEOUT phase=" + root.phase
                     + " pendingDl=" + root.pendingDownloadId
                     + " pendingJson=" + root.pendingJsonId
                     + " probing=" + root.probing)
            if (root.phase === "loading")
                root.showError("timeout")
        }
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

            // 占位/错误文案截断时悬停显示全文
            Components.ElideTip { anchors.fill: parent }
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
