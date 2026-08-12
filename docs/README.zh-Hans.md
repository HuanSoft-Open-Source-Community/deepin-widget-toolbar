<div align="center">

# 🧩 deepin-widget-toolbar（小组件工具栏）

![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)
![Qt 6](https://img.shields.io/badge/Qt-6.8+-green.svg)
![DTK 6](https://img.shields.io/badge/DTK-6.0+-orange.svg)
![dde-shell](https://img.shields.io/badge/dde--shell-2.0+-blue.svg)

面向 deepin 桌面、基于 dde-shell 插件体系的 Vista 风格小组件工具栏。

</div>

🌐 **语言**: [English](README.md) | [简体中文](README.zh-Hans.md) | [文言文](README.zh-Pre-Qin.md)

## ✨ 特性

- **📐 侧栏面板**：常驻于屏幕右侧的侧栏，宽度与通知中心一致（380 px）
- **📌 置顶/置底**：标题栏的 DTK 图钉按钮在*置顶*（始终在其他窗口之上，`LayerOverlay`）与*置底*（可被普通窗口覆盖，`LayerButtom`）之间切换
- **🔘 任务栏触发按钮**：dde-dock 托盘插件控制面板显隐——这是显示/隐藏的唯一途径，失焦不会自动关闭
- **💾 状态持久化**：`visible` 与 `pinned` 状态经 DConfig 持久化，重启后恢复
- **🖥️ 多屏支持**：面板跟随任务栏所在的屏幕

## 🏗️ 架构

两个插件通过会话总线 D-Bus 通信：

```
dde-shell 进程                            trayplugin-loader 进程
┌────────────────────────────────┐      ┌──────────────────────────────┐
│ org.deepin.ds.widgettoolbar    │      │ libwidget-toolbar.so         │
│  · DPanel 侧栏（380 px）        │◄────►│  · 任务栏托盘触发按钮          │
│  · 标题栏 + DTK 置顶按钮        │ D-Bus │  · 点击切换面板显隐            │
│  · LayerOverlay / LayerButtom  │      │  · 同步高亮状态               │
│  · DConfig 持久化              │      └──────────────────────────────┘
└────────────────────────────────┘
```

- **面板**（`panel/`）：dde-shell `DPanel` 插件（`org.deepin.ds.widgettoolbar`），注册 D-Bus 服务 `org.deepin.dde.widgettoolbar`，提供 `toggle()` / `show()` / `hide()` 方法与 `visible` / `pinned` 属性。
- **托盘按钮**（`tray/`）：dde-tray-loader 插件（`PluginsItemInterfaceV2`，`Type_Tray`），作为 D-Bus 客户端切换面板并反映其显隐状态。

## 📋 依赖要求

- deepin / UOS v25，dde-shell 2.0.52+（运行时）
- Qt 6.8+ 与 DTK 6 开发包
- `libdde-shell-dev`（2.0.52）
- dde-tray-loader 2.0.38（运行时，托盘插件需要）

## 🚀 构建

```bash
cmake -S . -B build
cmake --build build -j$(nproc)
```

## 📦 安装

```bash
sudo ./install.sh          # cmake --install build
systemctl --user restart dde-shell@DDE
```

## 🖱️ 使用

1. 点击任务栏托盘区的小组件工具栏按钮，显示或隐藏面板。
2. 点击面板标题栏的图钉按钮，切换置顶/置底：
   - **置顶**：面板始终位于所有窗口之上，点击面板外空白处不会关闭。
   - **置底**：普通窗口可以覆盖面板。
3. 显隐与置顶状态在重启后保持。

## ✅ 验证

- 面板出现在屏幕右侧，宽 380 px，带标题与置顶按钮。
- 任务栏按钮切换面板，其高亮跟随面板状态。
- 置顶时面板不被普通窗口覆盖；置底时可以被覆盖。
- 点击面板外空白处不会关闭面板。
- 重启后状态保持。

## 📁 目录结构

```
deepin-widget-toolbar/
├── CMakeLists.txt          # 顶层构建（panel + tray）
├── install.sh              # 系统安装脚本
├── docs/                   # 文档
│   ├── README.md           # 本文件（英文）
│   ├── README.zh-Hans.md   # 简体中文
│   ├── README.zh-Pre-Qin.md# 文言文（先秦文风）
│   └── LICENSE-GPL-3.0.txt # GNU GPL v3 全文
├── panel/                  # dde-shell DPanel 插件
│   ├── widgettoolbarpanel.*# DPanel + D-Bus 服务
│   ├── configs/            # DConfig 元数据
│   └── package/            # QML 界面（main.qml、PinButton.qml、图标）
└── tray/                   # dde-tray-loader 插件
    ├── widgettoolbartrayplugin.*  # PluginsItemInterfaceV2
    ├── traybutton.*        # 任务栏按钮 + D-Bus 客户端
    ├── interfaces/         # vendored dde-tray-loader 2.0.38 头文件
    └── icons/              # 按钮图标（QRC）
```

## 📜 许可证

本项目采用 [GNU 通用公共许可证 v3.0](LICENSE-GPL-3.0.txt)（或更高版本）。

`tray/interfaces/` 下的接口头文件来自 [dde-tray-loader](https://github.com/linuxdeepin/dde-tray-loader)，采用 LGPL-3.0-or-later 许可（见文件头）。
