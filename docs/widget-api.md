# 小组件接口规范（v0.1）

> 本文档定义 deepin-widget-toolbar 面板（宿主）与小组件之间的开放接口契约。
> 版本：0.1（对应接口规划草案的核心子集：清单 + 布局 + 渲染 + 实例上下文）。
> 完整演进草案见 `.tmp/todo/千问给的小组件接口规划.txt`。

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
| `apiVersion` | string | 是 | 所需接口版本，当前为 `1.1`；不兼容则宿主拒绝加载 |
| `author` | string | 否 | 作者 |
| `runtime` | string | 否 | 渲染运行时，当前仅支持 `qml`（默认值） |
| `entry` | string | 是 | 入口文件（相对小组件目录），如 `main.qml` |
| `defaultSize` | object | 是 | 默认占位 `{ "cols": 2, "rows": 2 }`；`cols ∈ [1,4]`，`rows ≥ 1` |
| `builtin` | bool | 内置专用 | 内置小组件标记（第三方包的 manifest 中应省略或为 false） |

## 4. 布局模型

- 网格 4 列，格子为正方形，宽 = 面板可用宽 / 4。
- 小组件占 `cols × rows` 个格子；添加时宿主按行扫描分配首个空闲矩形（`gridX/gridY`）。
- 实例位置与尺寸由宿主管理，小组件**不要**自设外部几何（`anchors.fill` 自身容器即可）。

## 5. 实例上下文（宿主注入）

小组件 QML 根对象可声明以下属性，宿主在加载后注入：

| 属性 | 类型 | 说明 |
|---|---|---|
| `instanceId` | string | 实例唯一标识（UUID），同一小组件可添加多个实例 |
| `dataDir` | string | 宿主隔离的实例数据目录：`~/.local/share/org.deepin.ds.widgettoolbar/widgets/<id>/data/`。持久化数据写入 `dataDir/<instanceId>.txt`（或自建子目录），按实例隔离 |

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
| `diskUsedPercent` | real | 根分区占用率 0~1（`QStorageInfo`） |

信号：`refreshed()`（默认每秒刷新；可用 `setRefreshInterval(ms)` 调整，下限 200ms）。

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
| `trackId` | string | 当前曲目的 `mpris:trackid` |

信号：`connectedChanged()`（总线上线/下线）、`lyricsChanged()`（快照内容变化，
重复/过期快照已按 payload 去重）。方法：`refresh()` 主动拉取一次快照。

## 7. 面板 API（预留）

以下接口为本规范预留，v0.1 尚未实现，未来版本按此契约提供：

| 接口 | 说明 |
|---|---|
| `requestRemoveSelf()` | 小组件请求从面板移除自身实例 |
| `requestResize(cols, rows)` | 小组件请求变更占位尺寸 |
| `showToast(message)` | 在面板层显示轻量提示 |
| `openUrl(url)` | 用系统默认浏览器/应用打开链接 |
| `getSettingsSchema()` / `onSettingsChanged(key, value)` | 配置项声明与变更回调（宿主自动生成设置 UI） |

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
- 当前宿主实现：`apiVersion = "1.1"`（v1.1 新增 `Lyrics` 歌词能力代理）。

## 10. 生命周期（v0.1 范围）

已实现：加载（添加 → 注入上下文 → 渲染）、移除实例、卸载（第三方）、数据持久化。

规划中（后续版本）：`onActivate/onDeactivate`（滚入/滚出可视区）、`onResize`、
`onSuspend/onResume`、`onThemeChanged` 主题令牌下发、网络/DBus 权限模型、事件总线。

## 11. 已知限制

- 网格暂不支持拖拽调整位置与尺寸（占位固定为 manifest 的 `defaultSize`）。
- 小组件设置页（`getSettingsSchema` 自动生成）未实现。
- 网络请求未开放；小组件不允许直接访问系统 D-Bus，只能使用宿主能力代理
  （`FileIO` / `SystemInfo` / `Lyrics`）。
- 小组件间事件总线（`bus.emit/on`）未实现。
