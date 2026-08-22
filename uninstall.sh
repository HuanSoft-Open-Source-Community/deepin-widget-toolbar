#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# deepin-widget-toolbar 一键卸载脚本：删除系统与用户残留 -> 清理缓存（可选用户数据）-> 重启 dde-shell。
#
# 用法：./uninstall.sh   （无需参数；删除系统文件时自动请求 sudo 密码）
# 请以普通用户运行本脚本（内部自动请求管理员权限），勿加 sudo。
set -euo pipefail

PLUGIN_ID="org.deepin.ds.widgettoolbar"
TRAY_PLUGIN="libwidget-toolbar.so"

if [ "$(id -u)" = "0" ]; then
    echo "错误：请以普通用户运行 ./uninstall.sh（脚本内部会自动请求 sudo 密码，勿加 sudo）" >&2
    exit 1
fi

echo "==> [1/4] 删除系统插件文件（请求管理员权限）"
sudo -v || { echo "错误：需要 sudo 权限删除系统插件文件" >&2; exit 1; }
sudo rm -f "/usr/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so"
sudo rm -rf "/usr/share/dde-shell/${PLUGIN_ID}"
sudo rm -f "/usr/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json"
sudo rm -f "/usr/lib/dde-dock/plugins/${TRAY_PLUGIN}"
sudo rm -rf "/usr/share/widget-toolbar"
sudo rm -f "/usr/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci"

echo "==> [2/4] 清理旧路径与用户目录残留"
# 旧部署路径（/usr/local 及 /var/usrlocal 映射）残留，存在才删
for base in /usr/local /var/usrlocal; do
    [ -e "${base}/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so" ] && sudo rm -f "${base}/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so"
    [ -e "${base}/share/dde-shell/${PLUGIN_ID}" ] && sudo rm -rf "${base}/share/dde-shell/${PLUGIN_ID}"
    [ -e "${base}/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json" ] && sudo rm -f "${base}/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json"
    [ -e "${base}/lib/dde-dock/plugins/${TRAY_PLUGIN}" ] && sudo rm -f "${base}/lib/dde-dock/plugins/${TRAY_PLUGIN}"
    [ -e "${base}/share/widget-toolbar" ] && sudo rm -rf "${base}/share/widget-toolbar"
    [ -e "${base}/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci" ] && sudo rm -f "${base}/share/dde-dock/icons/dcc-setting/dcc-widget-toolbar.dci"
done
# 用户目录部署/残留
rm -f "${HOME}/.local/lib/dde-shell/${PLUGIN_ID}.so"
rm -rf "${HOME}/.local/share/dde-shell/${PLUGIN_ID}"

echo "==> [3/4] 清理缓存与用户数据"
rm -rf "${HOME}/.cache/${PLUGIN_ID}" \
       "${HOME}/.cache/dde-shell/${PLUGIN_ID}"
# 用户小组件数据（已添加实例清单 installed.json + 内置/第三方小组件数据目录）
if [ -e "${HOME}/.local/share/${PLUGIN_ID}" ]; then
    if [ -t 0 ]; then
        read -r -p "是否同时删除用户小组件数据 ${HOME}/.local/share/${PLUGIN_ID} ？[y/N] " ans
    else
        ans=""
    fi
    case "${ans}" in
        y|Y|yes|YES)
            rm -rf "${HOME}/.local/share/${PLUGIN_ID}"
            echo "  已删除用户小组件数据"
            ;;
        *)
            echo "  保留用户小组件数据（如需删除：rm -rf ~/.local/share/${PLUGIN_ID}）"
            ;;
    esac
fi
# 注：DConfig 用户态覆盖记录在 ~/.config/deepin/org.deepin.dde-shell/settings.ini，
#     与其他 dde-shell 配置共用，不在此删除。

echo "==> [4/4] 重启 dde-shell（卸载生效，托盘图标随之移除）"
systemctl --user restart dde-shell@DDE.service \
    || { echo "警告：dde-shell 重启失败，请手动执行：systemctl --user restart dde-shell@DDE" >&2; exit 1; }

echo
echo "卸载完成：插件文件、旧路径与缓存残留已清理，任务栏托盘图标已移除。"
echo "提示：若通过 .deb 安装过，请另行执行：sudo dpkg -r deepin-widget-toolbar"
