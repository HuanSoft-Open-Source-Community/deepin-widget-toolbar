#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# deepin-widget-toolbar 一键安装脚本：自动构建 -> 请求管理员权限部署 -> 重启 dde-shell。
#
# 用法：./install.sh   （无需参数；部署到系统目录时自动请求 sudo 密码）
#   - 面板：/usr/lib/x86_64-linux-gnu/dde-shell/org.deepin.ds.widgettoolbar.so
#           /usr/share/dde-shell/org.deepin.ds.widgettoolbar/（package + 翻译）
#           /usr/share/dsg/configs/org.deepin.dde.shell/org.deepin.ds.widgettoolbar.json
#   - 托盘：/usr/lib/dde-dock/plugins/libwidget-toolbar.so
#           /usr/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci
#           /usr/share/widget-toolbar/translations/*.qm
# 说明：运行中的 dde-shell 只搜索 /usr/lib/x86_64-linux-gnu/dde-shell 下的插件库，
#       因此 .so 必须装到系统目录（需要 sudo），QML 包与 DConfig 元数据同理。
#       请以普通用户运行本脚本（内部自动请求管理员权限），勿加 sudo。
set -euo pipefail

PLUGIN_ID="org.deepin.ds.widgettoolbar"
TRAY_PLUGIN="libwidget-toolbar.so"

if [ "$(id -u)" = "0" ]; then
    echo "错误：请以普通用户运行 ./install.sh（脚本内部会自动请求 sudo 密码，勿加 sudo）" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
cd "${REPO_ROOT}"

echo "==> [1/5] 检查构建环境"
for cmd in cmake sudo systemctl; do
    command -v "${cmd}" >/dev/null 2>&1 || { echo "错误：缺少命令 ${cmd}" >&2; exit 1; }
done

echo "==> [2/5] 构建插件（增量）"
# 幂等配置：无缓存则生成；已有缓存则校正安装前缀为 /usr
# （/usr/local 前缀的部署不被运行中的 dde-shell 搜索，会导致插件不生效）。
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
[ -f "build/plugins/${PLUGIN_ID}.so" ] || { echo "错误：构建产物缺失 build/plugins/${PLUGIN_ID}.so" >&2; exit 1; }
[ -f "build/tray/${TRAY_PLUGIN}" ] || { echo "错误：构建产物缺失 build/tray/${TRAY_PLUGIN}" >&2; exit 1; }

echo "==> [3/5] 部署到系统目录（请求管理员权限）"
sudo -v || { echo "错误：需要 sudo 权限安装到系统目录" >&2; exit 1; }
sudo cmake --install build

echo "==> [4/5] 清理不会生效的旧副本"
# 用户目录部署不被运行中的 dde-shell/dde-dock 搜索，且旧副本会遮蔽系统包，一并清除
rm -f "${HOME}/.local/lib/dde-shell/${PLUGIN_ID}.so"
rm -rf "${HOME}/.local/share/dde-shell/${PLUGIN_ID}"
for base in /usr/local /var/usrlocal; do
    [ -e "${base}/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so" ] && sudo rm -f "${base}/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so"
    [ -e "${base}/share/dde-shell/${PLUGIN_ID}" ] && sudo rm -rf "${base}/share/dde-shell/${PLUGIN_ID}"
    [ -e "${base}/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json" ] && sudo rm -f "${base}/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json"
    [ -e "${base}/lib/dde-dock/plugins/${TRAY_PLUGIN}" ] && sudo rm -f "${base}/lib/dde-dock/plugins/${TRAY_PLUGIN}"
    [ -e "${base}/share/widget-toolbar" ] && sudo rm -rf "${base}/share/widget-toolbar"
    [ -e "${base}/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci" ] && sudo rm -f "${base}/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci"
done

echo "==> [5/5] 重启 dde-shell（面板与托盘随其一并重载）"
# 托盘插件由 dde-shell 的 dock fork 出的 trayplugin-loader 进程加载，重启 dde-shell 即全部生效
systemctl --user restart dde-shell@DDE.service \
    || { echo "警告：dde-shell 重启失败，请手动执行：systemctl --user restart dde-shell@DDE" >&2; exit 1; }

echo
echo "安装完成："
echo "  面板 .so  → /usr/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so"
echo "  面板 QML  → /usr/share/dde-shell/${PLUGIN_ID}/"
echo "  托盘 .so  → /usr/lib/dde-dock/plugins/${TRAY_PLUGIN}"
echo "请在任务栏托盘区点击图标验证：左键显隐、右键菜单（添加/整理/设置/关于）。"
