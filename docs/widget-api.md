# 小组件接口规范（v1.5）

> 本文档定义 deepin-widget-toolbar 面板（宿主）与小组件之间的开放接口契约。
> 当前宿主接口版本：1.5；同时兼容 1.0/1.1/1.2/1.3/1.4 小组件。

## 1. 架构

- **宿主（Panel）**：`org.deepin.ds.widgettoolbar` 侧栏，负责网格布局、生命周期、实例清单持久化、能力代理。
- **小组件（Widget）**：携带 `manifest.json` 的独立 QML 单元，通过本文档接口与宿主交互。
- **布局模型**：网格制。横向固定 4 列，纵向无限行、可滚动。最小占位 1 格（1 col × 1 row）。

## 2. 小组件包结构

一个小组件 = 一个目录，包含：

```
<widget-id>/
├── manifest.json     # 必填：清单与元数据
└── main.qml          # 入口（由 manifest.entry 指定）
```

- **内置小组件**：编译进宿主的 qrc 资源（`qrc:/widgets/<id>/`），不可卸载。
- **第三方小组件**：位于 `~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/`，
  可通过"添加面板 → 从 .dwpkg 文件安装"导入，可卸载。

## 3. manifest.json 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 全局唯一标识，`^[A-Za-z0-9._-]+$`（反向域名风格，如 `com.example.weather`） |
| `name` | string | 是 | 显示名称（默认语言） |
| `name[zh_CN]` | string | 否 | 指定语言的显示名称（`name[<locale>]` 通用） |
| `description` | string | 否 | 一句话描述 |
| `icon` | string | 否 | 主题图标名（如 `appointment-new`），面板列表中显示 |
| `version` | string | 是 | 语义化版本号，如 `1.0.0` |
| `apiVersion` | string | 是 | 所需接口版本，当前为 `1.3`；宿主兼容所有 `1.x`，不兼容则拒绝加载 |
| `author` | string | 否 | 作者 |
| `runtime` | string | 否 | 渲染运行时，当前仅支持 `qml`（默认值） |
| `entry` | string | 是 | 入口文件（相对小组件目录），如 `main.qml` |
| `defaultSize` | object | 是 | 默认占位 `{ "cols": 2, "rows": 2 }`；`cols ∈ [1,4]`，`rows ≥ 1` |
| `sizes` | array | 否 | 可选尺寸数组，元素为 `{ "cols": 1, "rows": 1 }`；缺失时只允许 `defaultSize`，且 `defaultSize` 必须包含在其中 |
| `settings` | array | 否 | 配置项声明，供宿主生成右键“配置…”面板；元素字段见下文 |
| `builtin` | bool | 内置专用 | 内置小组件标记（第三方包的 manifest 中应省略或为 false） |

配置 schema 元素字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `key` | string | 配置键，不能为空 |
| `type` | string | `boolean` / `enum` / `color` / `font` / `string` / `integer` / `timezoneList` / `player` |
| `label` / `label[locale]` | string | 显示名称及本地化名称 |
| `default` | 任意 | 默认值 |
| `options` | array | `enum`/`color` 的候选项，元素含 `value`、`label`、`label[locale]`；`font` 的候选由宿主从 `Qt.fontFamilies()` 生成；`timezoneList` 的候选由宿主从 `Timezones` 生成；`player` 的候选由宿主从 `MediaPlayers.players` 生成 |

颜色类配置值统一为 `#RRGGBB` 或 `#AARRGGBB`（`AARRGGBB` 用于带透明度的默认色）。宿主/小组件在渲染前必须校验：
非法值回退到 manifest 默认色，避免脏配置导致渲染异常。内置小组件统一提供
`transparentBackground`（boolean，默认 `false`）开关：开启时隐藏卡片与内部区域底色（日历/便签等含区域底色的组件一并透明），文字与内容仍保留。

`timezoneList` 的值形如 `[{ "zone": "Asia/Shanghai", "auto": false }]`：
`zone` 为控制中心时区 id，`auto` 标记是否为缩放补位生成。宿主配置面板渲染为
“时区下拉 + 删除”行列表及“添加”按钮；改过任一行会把 `auto` 置为 false。

`player` 类型的值是一个 MPRIS 会话总线服务名（如 `org.mpris.MediaPlayer2.vlc`），
由宿主动态枚举；当前无播放器时下拉为空且禁用。配置面板应在 `playerMode` 为
`locked` 时才显示该行。

内置组件示例：clock 允许 `1×1 / 2×2 / 4×2 / 4×4` 并声明 `clockMode` 配置；lyrics 声明 `lyricsFont` 与 `lyricsColor`。

## 4. 布局模型

- 网格 4 列，格子为正方形，宽 = 面板可用宽 / 4。
- 小组件占 `cols × rows` 个格子；位置默认持久保持，宿主不强制自动补位。
- 新增实例时放入首个空闲矩形，不移动现有实例；移除实例时其余实例保持原位（留洞），仅点击"整理"按钮时按清单顺序左上优先压实。
- 拖放：长按拖拽到任意可容纳格子（含每行非首列）；拖拽过程中目标格被占用时，占用者实时让位（保持列号、只调行号，可上可下、多组件联动），移开目标或取消则回弹，松手后位置持久化；所有位置变化由宿主以动画呈现。
- 实例位置与尺寸由宿主管理，小组件**不要**自设外部几何（`anchors.fill` 自身容器即可）。

## 5. 实例上下文（宿主注入）

小组件 QML 根对象可声明以下属性，宿主在加载后注入：

| 属性 | 类型 | 说明 |
|---|---|---|
| `instanceId` | string | 实例唯一标识（UUID），同一小组件可添加多个实例 |
| `dataDir` | string | 宿主隔离的实例数据目录：`~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/data/`。持久化数据写入 `dataDir/<instanceId>.txt`（或自建子目录），按实例隔离 |
| `widgetConfig` | object | 该实例的配置对象（由 `settings` schema 默认值与已保存配置合并），配置面板保存后宿主刷新该属性 |

## 6. 宿主能力代理（QML 模块 `org.deepin.widgettoolbar 1.0`）

小组件 `import org.deepin.widgettoolbar 1.0` 后可使用宿主提供的单例：

### FileIO（文件读写，沙箱约束）

> **沙箱**：仅允许访问小组件数据根目录（`~/.local/share/org.deepin.ds.widgettoolbar/widgets/`）内的路径，
> 其他路径一律拒绝（返回空/失败）。请配合 `dataDir` 使用。

| 方法 | 签名 | 说明 |
|---|---|---|
| `readTextFile` | `string readTextFile(string path)` | 读取文本文件，失败返回空串 |
| `writeTextFile` | `bool writeTextFile(string path, string content)` | 写入文本（自动创建父目录） |
| `exists` | `bool exists(string path)` | 判断文件是否存在 |

### SystemInfo（系统监视数据）

| 属性 | 类型 | 说明 |
|---|---|---|
| `cpuUsage` | real | CPU 使用率 0~1（读 `/proc/stat` 差值） |
| `memUsedPercent` | real | 内存使用率 0~1（读 `/proc/meminfo`） |
| `diskUsedPercent` | real | 兼容旧接口：根分区空间占用率 0~1（`QStorageInfo`），新组件请使用 `diskBusyPercent` |
| `diskBusyPercent` | real | 磁盘 IO 忙时利用率 0~1（iostat `%util`，聚合非 loop/非分区物理设备） |
| `gpuUsage` / `gpuAvailable` | real / bool | 当前 GPU 占用与可读状态；不可用时 `gpuAvailable=false` 且 `gpuUsage=0` |
| `npuUsage` / `npuAvailable` | real / bool | 当前 NPU 占用与可读状态；不可用时 `npuAvailable=false` 且 `npuUsage=0` |

指标口径、sysfs/NVML 数据源与降级策略详见 [system-monitor.md](system-monitor.md)。

采样在宿主后台线程执行，不阻塞 dde-shell 主线程。系统监视小组件使用
`updateMonitor(clientId, active, metrics, intervalMs)` 声明自身实例的指标需求，
并在销毁时调用 `releaseMonitor(clientId)`。SystemInfo 会合并所有活动客户端的指标并集，
按其中最小刷新间隔采样；任一客户端释放不会影响其他客户端。
指标 id 为 `cpu` / `mem` / `disk` / `gpu` / `npu`（兼容项 `diskUsed`）。
旧接口 `setMonitoringActive(bool)`、`setMonitoredMetrics(metrics)`、`setRefreshInterval(ms)`
继续兼容第三方小组件；刷新间隔下限为 1000ms，默认 5000ms。

信号：各属性都有独立变化信号（如 `cpuUsageChanged`）；`refreshed()` 作为任一指标
变化的兼容信号，仅在采样值变化达到展示阈值或可用状态变化时发出。

### Lyrics（端闱乐部歌词数据）

> **系统 D-Bus 能力代理**：小组件不允许直接访问系统 D-Bus，歌词数据统一由宿主
> 代理 `org.mpris.MediaPlayer2.ter_music` 会话总线名上的
> `org.yxzl.ter_music.Lyrics` 接口（`GetLyrics` / `LyricsChanged`），
> 解析 A/B 双缓冲歌词快照后暴露。播放器未运行时自动降级为未连接状态；
> 接口契约详见 Ter-Music 的 `docs/API_LYRICS_en_US.md`。

| 属性 | 类型 | 说明 |
|---|---|---|
| `connected` | bool | 端闱乐部是否持有 MPRIS 总线名（进程正在运行） |
| `hasTrack` | bool | 是否有曲目在播放（`track_id` 非空） |
| `hasLyrics` | bool | 当前曲目是否加载了歌词 |
| `hasTimestamps` | bool | 歌词是否带 LRC 时间戳 |
| `activeText` | string | 当前句文本（`active_line` 指向的槽位） |
| `nextText` | string | 下一句文本（另一槽位） |
| `lineAText` | string | A/B 双缓冲中槽 A 的歌词文本（空槽为空串） |
| `lineBText` | string | A/B 双缓冲中槽 B 的歌词文本（空槽为空串） |
| `activeLineA` | bool | 当前活动槽是否为 A（`active_line == "A"`；`null` 按 A 处理） |
| `trackId` | string | 当前曲目的 `mpris:trackid` |

信号：`connectedChanged()`（总线上线/下线）、`lyricsChanged()`（快照内容变化，
重复/过期快照已按 payload 去重）。方法：`refresh()` 主动拉取一次快照。

### MediaPlayers / MediaPlayer（MPRIS 播放器）

> **系统 D-Bus 能力代理**：小组件不允许直接访问系统 D-Bus。宿主提供
> `MediaPlayers` 单例枚举/监控 MPRIS 播放器，并提供可创建类型 `MediaPlayer`
> 作为每个播放控制器实例的播放器代理（自动或锁定选择、订阅属性、转发控制与 seek）。
>
> **信任边界**：该代理对所有小组件开放。MPRIS 属于同一用户会话的信任边界，
> 任何持有会话总线权限的进程都可以注册 MPRIS 服务名、扮演播放器或控制播放器；
> `http(s)` 封面 URL 会由面板发起网络请求，属已接受风险。

`MediaPlayers`（单例）：

| 属性/方法 | 类型 | 说明 |
|---|---|---|
| `players` | var | `[{service, name}]`，按服务名排序；`playersChanged()` 在列表变化时发出 |
| `activeService` | string | 最近产生播放器信号的服务（auto 模式首选） |
| `playerName(service)` | string | 播放器显示名（Identity，未取到时用服务名后缀） |
| `serviceNames()` | string[] | 当前 MPRIS 服务名列表 |
| `isRunning(service)` | bool | 指定服务当前是否持有总线名 |

`MediaPlayer`（每实例一个）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `mode` | string | `auto` 或 `locked`（锁定到 `service`） |
| `service` | string | locked 模式下的目标 MPRIS 服务名 |
| `connected` / `hasTrack` | bool | 是否已连接 / 是否有曲目元数据 |
| `playbackStatus` | string | `Playing` / `Paused` / `Stopped` / 空 |
| `title` / `artist` / `artUrl` | string | 当前曲目元数据（artist 为数组时以逗号连接） |
| `positionMs` / `lengthMs` | int | 进度（播放中按 Rate 插值）与曲目时长 |
| `canSeek` / `canControl` | bool | 是否允许 seek / 控制（`CanSeek`/`CanControl`） |
| `canGoNext` / `canGoPrevious` / `canPlay` / `canPause` | bool | 控制能力门控 |

`Rate` 来自播放器元数据，宿主只接受有限且 `(0, 16]` 范围内的值；非有限、
`<= 0` 的值回退为 `1.0`，超过 `16.0` 的值钳制为 `16.0`。插值结果始终
限制在 `[0, lengthMs]` 内。

| 方法 | 签名 | 说明 |
|---|---|---|
| `playPause()` | void | 播放/暂停（受 `CanControl`/`CanPlay`/`CanPause` 门控） |
| `next()` / `previous()` | void | 下一曲/上一曲（受对应能力门控） |
| `seek(ms)` | void | 绝对 seek（受 `CanSeek` 门控，内部优先 `SetPosition`，无 trackid 时回退 `Seek` 偏移） |
| `refresh()` | void | 主动重新拉取播放器属性 |

信号：`stateChanged()` 在任一状态/元数据/进度/能力变化时发出。`mpris:artUrl`
由小组件直接作为 `Image.source` 使用；宿主只接受 `file://`、`http://`、
`https://` 三种 scheme，其余 URL 会清空并触发小组件回退内置占位图标。
封面 URL 只来自播放器元数据，不来自小组件配置。

### Timezones（控制中心时区数据）

> **系统 D-Bus 能力代理**：小组件不允许直接访问系统 D-Bus。世界时间等组件经本代理
> 读取 DDE 控制中心“时间设置”使用的时区数据，数据源为会话总线
> `org.deepin.dde.Timedate1`（与控制中心 datetime 插件一致）。

| 属性 | 类型 | 说明 |
|---|---|---|
| `available` | bool | 会话总线上的 Timedate1 服务是否可用 |
| `systemTimezone` | string | 系统时区 id（如 `Asia/Shanghai`） |
| `userTimezones` | string[] | 控制中心“时间设置”维护的用户时区 id 列表，首个为系统时区 |

| 方法 | 签名 | 说明 |
|---|---|---|
| `displayName` | `string displayName(string zoneId)` | 时区的本地化地区名（daemon 按当前语言返回，未写入组件 ts）；失败回退为时区 id 末段 |
| `offsetSeconds` | `int offsetSeconds(string zoneId)` | 当前 UTC 偏移秒（与控制中心口径一致，DST 生效期间为 DST 偏移） |
| `zoneIds` | `string[] zoneIds()` | 控制中心时区选择器使用的完整时区列表（`GetZoneList` 顺序） |
| `firstZoneForOffset` | `string firstZoneForOffset(int offsetHours, string[] excludeZones)` | 当前偏移等于给定小时数的时区中，按 `GetZoneList` 顺序、跳过 `excludeZones` 后取第一个 id；无则空串 |
| `zoneOptions` | `var zoneOptions()` | 时区下拉选项 `[{value, label}]`（本地化地区名）；首次调用返回当前缓存并触发后台加载，加载完成后发出 `zoneOptionsChanged()` |

信号：`availableChanged()`、`systemTimezoneChanged()`、`userTimezonesChanged()`、
`zoneOptionsChanged()`（后台时区选项加载完成）。
地区名与时差直接来自控制中心的本地化数据，因此无需在小组件 ts 中维护时区名。

### ClockTime（预加载时间源）

> **性能优化**：时钟、世界时钟等需要秒级刷新的小组件应优先订阅本单例，
> 而不是各自创建 `Timer`。宿主只维护一个按系统整秒对齐的定时器，同一秒只
> 广播一次，所有订阅者拿到同一个时间快照，避免大量表盘重复读系统时间、
> 各自建 Timer 以及在同秒集中重绘造成的卡顿。

| 属性/方法 | 类型 | 说明 |
|---|---|---|
| `epochMs` | real | 当前 Unix 毫秒时间戳（整秒广播的快照，同一秒内所有订阅者一致） |
| `refresh()` | void | 立即补发一次当前整秒时间并重新对齐下一次广播 |

信号：`epochMsChanged()`（整秒变化时发出；同一秒内只发一次）。

### WidgetHost（实例配置回写）

| 方法 | 签名 | 说明 |
|---|---|---|
| `saveConfig` | `bool saveConfig(string instanceId, object values)` | 保存该实例的配置；仅允许 manifest `settings` 中声明的 key，供小组件在运行期（如缩放补位）持久化设置 |
| `usedZones` | `string[] usedZones(string excludingInstanceId)` | 其它实例 `dials` 配置中已使用的时区 id（世界时间跨实例地区唯一性用） |

### AudioVisualizer（系统音频频谱）

> **音频服务能力代理**：小组件不允许直接访问音频服务（PulseAudio/PipeWire/ALSA）。
> 宿主在独立线程以 `dlopen` 方式按优先级动态选择后端，记录**系统正在播放的
> 音频回环**，对 PCM 做 FFT 后输出 32 带 0..100 频谱快照。频谱面板小组件经
> 本代理实现随系统音频自由跃动的可视化。
>
> **后端动态选择**（纯自动，故障降级 / 恢复）：
> - `PulseAudio`：`dlopen libpulse.so.0`，记录默认 sink 的 monitor 源，覆盖
>   纯 PulseAudio 与 PipeWire+pipewire-pulse 系统（deepin/UOS 均为此类）；
> - `PipeWire`：`dlopen libpipewire-0.3.so.0`，注册表枚举真实 Audio/Sink 节点，
>   以 sink 节点为 target 创建 input 流（路由到其 monitor 端口），用于无
>   pipewire-pulse 的系统；
> - `ALSA`：`dlopen libasound.so.2`，**仅**在检测到 `snd-aloop` 的 Loopback
>   卡时启用并采集回环设备，用于纯 ALSA 回环环境。
>
> **安全边界**：
> - 采集目标只能是输出回环：Pulse 侧只接受以 `.monitor` 结尾的源，PipeWire
>   侧只枚举 `Audio/Sink` 节点，ALSA 侧只接受 Loopback 卡；**任何情况下绝不
>   回退到麦克风等输入源**（不触碰 `alsa_input.*` / `Audio/Source`）。
> - 仅暴露只读数值接口，小组件拿不到原始 PCM，也没有任何写入口；
> - 采集仅在有实例可见且面板可见时进行（`setActive` 引用计数），全部实例
>   释放后立即停流停分析；分析节流约 30Hz，FFT 固定 128 点，开销极小；
> - 数据仅内存计算，不落盘、不联网、不触发任何系统 D-Bus 调用。

| 属性/方法 | 类型 | 说明 |
|---|---|---|
| `available` | bool | 采集流是否就绪（可捕获系统音频）；音频服务缺失/无默认 sink monitor 时为 false |
| `bandCount` | int | 频谱带数（固定 32） |
| `levels` | var | 最近一帧频谱快照（32 个 0..100 整数，约 30Hz 更新，`levelsChanged()` 通知） |
| `active` | bool | 是否有实例正在采集（任一侧栏实例可见且面板可见） |
| `setActive(clientId, active)` | void | 实例注册/注销采集需求；clientId 通常为实例 UUID，按引用计数，重复调用幂等 |

信号：`availableChanged()`（采集就绪状态翻转）、`levelsChanged()`（新一帧频谱）、
`activeChanged()`（采集开/停）。小组件应在可见时 `setActive(instanceId, true)`、
隐藏/销毁时 `setActive(instanceId, false)`，避免无谓采集。

## 7. 面板 API（预留）

以下接口为本规范预留，尚未实现，未来版本按此契约提供：

| 接口 | 说明 |
|---|---|
| `requestRemoveSelf()` | 小组件请求从面板移除自身实例 |
| `requestResize(cols, rows)` | 小组件请求变更占位尺寸 |
| `showToast(message)` | 在面板层显示轻量提示 |
| `openUrl(url)` | 用系统默认浏览器/应用打开链接 |
| `getSettingsSchema()` / `onSettingsChanged(key, value)` | 兼容旧规范名称；1.2 起配置已通过 manifest `settings` 与 `widgetConfig` 提供 |

## 8. .dwpkg 包格式（第三方分发）

- 本质：`tar.xz` 压缩包（压缩率高）。
- 内容：小组件目录（含 `manifest.json` 与入口文件），包根或第一层子目录均可。
- 导入流程（宿主侧）：列出包内容校验路径安全（拒绝 `..` 与绝对路径）→ 解压到临时目录 →
  查找并解析 `manifest.json` → 校验 `id` 合法且未安装 → 移动到
  `~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/`。
- 卸载：删除该目录（内置小组件拒绝卸载）。

## 9. 版本兼容策略

- 小组件声明 `apiVersion`；宿主加载时校验，不兼容则拒绝加载并提示，不静默失败。
- 宿主新增接口走次版本递增，不破坏既有小组件（1.0 小组件仍可加载）。
- 当前宿主实现：`apiVersion = "1.5"`（1.1 新增 `Lyrics`；1.2 新增 `sizes`、`settings`、`widgetConfig` 及 GPU/NPU/磁盘 IO 监控；1.3 新增 `SystemInfo.updateMonitor` / `releaseMonitor` 多客户端监控；1.4 新增 `MediaPlayers` / `MediaPlayer` 与 `player` 设置类型；1.5 新增 `AudioVisualizer` 系统音频频谱代理）。

## 10. 生命周期（当前范围）

已实现：加载（添加 → 注入上下文 → 渲染）、移除实例、卸载（第三方）、数据持久化。

规划中（后续版本）：`onActivate/onDeactivate`（滚入/滚出可视区）、`onResize`、
`onSuspend/onResume`、`onThemeChanged` 主题令牌下发、网络/DBus 权限模型、事件总线。

## 11. 已知限制

- 网格支持长按拖放调整位置；右键菜单可切换 `sizes` 声明的占位尺寸，切换时冲突实例联动避让并持久化。
- 小组件设置页由 manifest `settings` schema 自动生成，支持列出的基础类型及 `timezoneList`。
- 网络请求未开放；小组件不允许直接访问系统 D-Bus 与音频服务，只能使用宿主能力代理
  （`FileIO` / `SystemInfo` / `Lyrics` / `Timezones` / `ClockTime` / `WidgetHost` / `MediaPlayers` / `MediaPlayer` / `AudioVisualizer`）。
- 小组件间事件总线（`bus.emit/on`）未实现。
