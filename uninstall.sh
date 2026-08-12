#!/bin/bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

# 卸载 deepin-widget-toolbar（与 install.sh 配套，需要 root：sudo ./uninstall.sh）：
#   - 面板：/usr/lib/x86_64-linux-gnu/dde-shell/org.deepin.ds.widgettoolbar.so
#           /usr/share/dde-shell/org.deepin.ds.widgettoolbar/（package + 翻译）
#           /usr/share/dsg/configs/org.deepin.dde.shell/org.deepin.ds.widgettoolbar.json
#   - 托盘：/usr/lib/dde-dock/plugins/libwidget-toolbar.so
#           /usr/share/widget-toolbar/（翻译）
set -e

echo "==> Removing panel plugin (dde-shell)..."
rm -rfv /usr/lib/x86_64-linux-gnu/dde-shell/org.deepin.ds.widgettoolbar.so \
        /usr/share/dde-shell/org.deepin.ds.widgettoolbar \
        /usr/share/dsg/configs/org.deepin.dde.shell/org.deepin.ds.widgettoolbar.json

echo "==> Removing tray plugin (dde-dock)..."
rm -rfv /usr/lib/dde-dock/plugins/libwidget-toolbar.so \
        /usr/share/widget-toolbar

echo
echo "==> Done. Restart dde-shell to apply:"
echo "    systemctl --user restart dde-shell@DDE"
echo
echo "Optional: remove user-level state:"
echo "    rm -f ~/.config/deepin/org.deepin.dde.shell/*widgettoolbar*   # DConfig (visible/pinned)"
echo "    rm -rf ~/.local/share/org.deepin.ds.widgettoolbar             # 第三方小组件 + installed.json + 实例数据"
