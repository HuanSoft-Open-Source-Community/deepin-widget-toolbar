<div align="center">

# 🧩 深之小组件欄（deepin-widget-toolbar）

![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)
![Qt 6](https://img.shields.io/badge/Qt-6.8+-green.svg)
![DTK 6](https://img.shields.io/badge/DTK-6.0+-orange.svg)
![dde-shell](https://img.shields.io/badge/dde--shell-2.0+-blue.svg)

deepin 桌面之側欄也，仿 Vista 之制，依 dde-shell 插件之體。

</div>

🌐 **諸文**: [English](README.md) | [簡體中文](README.zh-Hans.md) | [文言](README.zh-Pre-Qin.md)

## 序

此器者，小组件欄也。居屏之右，廣三百八十素，與通知中心同寬。欄首有題，其右有圖釘之鈕，可按而置頂置底：置頂則恆居萬窗之上，置底則凡窗皆可覆之。任務欄復有鈕焉，按之則欄顯，再按之則欄隱，此外無他途可闔。故雖點欄外之空處，欄終不閉。顯隱之態與置頂之態，皆記之於 DConfig，重啟而復焉。屏之多者，欄隨任務欄所居之屏而徙。

## 構

先備 Qt6、DTK6、libdde-shell-dev 之屬，然後：

```bash
cmake -S . -B build
cmake --build build -j$(nproc)
```

## 裝

```bash
sudo ./install.sh
systemctl --user restart dde-shell@DDE
```

## 用

點任務欄之鈕，欄或顯或隱。點欄首之圖釘，欄或置頂或置底。二態既記，重啟不失。

## 文

斯文有三：英文為正，簡體為輔，此文以先秦文言述之，三文互為援引，覽者擇其宜焉。

## 律

此器行 GNU GPL v3.0 之律，全文見 [LICENSE](../LICENSE)。`tray/interfaces/` 之頭文件出自 [dde-tray-loader](https://github.com/linuxdeepin/dde-tray-loader)，行 LGPL-3.0-or-later 之律，詳見文件之首。
