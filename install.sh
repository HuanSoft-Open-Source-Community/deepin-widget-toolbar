#!/bin/bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

# 安装 deepin-widget-toolbar 到系统（需要 root）：
#   - 面板：/usr/lib/x86_64-linux-gnu/dde-shell/org.deepin.ds.widgettoolbar.so
#           /usr/share/dde-shell/org.deepin.ds.widgettoolbar/（package + DConfig 元数据）
#   - 托盘：/usr/lib/dde-dock/plugins/libwidget-toolbar.so
#           /usr/share/widget-toolbar/translations/*.qm
set -e
cd "$(dirname "$0")"

cmake --install build

echo
echo "安装完成。重启 dde-shell 使插件生效："
echo "  systemctl --user restart dde-shell@DDE"
