#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# deepin-widget-toolbar 一键卸载脚本：确认清理范围（可选面板设置）-> 删除系统与用户残留 ->
# 清理缓存（可选用户数据）-> 重启 dde-shell。
#
# 用法：./uninstall.sh   （无需参数；删除系统文件时自动请求 sudo 密码）
# 请以普通用户运行本脚本（内部自动请求管理员权限），勿加 sudo。
set -euo pipefail

PLUGIN_ID="org.deepin.ds.widgettoolbar"
TRAY_PLUGIN="libwidget-toolbar.so"
# DConfig 应用 Id 与配置项，与面板代码里 DConfig::create("org.deepin.dde.shell", PLUGIN_ID)
# 一致。只 reset 本插件这几个键，绝不触碰 dde-shell 的其它配置（如 dock）。
DCONFIG_APPID="org.deepin.dde.shell"
DCONFIG_KEYS=(visible pinned cardTransparent showCardNames debugMode)

if [ "$(id -u)" = "0" ]; then
    echo "错误：请以普通用户运行 ./uninstall.sh（脚本内部会自动请求 sudo 密码，勿加 sudo）" >&2
    exit 1
fi

# 面板设置的清理：面板的显隐/置顶/卡片透明/卡片名称/调试日志都是 DConfig 配置项，用户改动会形成
# "用户覆盖"并由 dde-dconfig 守护进程按 uid 持久化（存放于 /var/lib/dde-dconfig-daemon，
# root 私有，删 ~/.config 下的文件清不掉），所以重装会沿用上次的选择——例如卡片透明模式
# 仍是开启，看起来像"缺省值不对"。只能经官方 CLI reset 回到配置描述文件里声明的默认值，
# 而 reset 要求该描述文件仍在，故这一步必须先于 [1/4] 的删除动作。
purge_settings=""
if [ -t 0 ]; then
    read -r -p "是否清除本插件的面板设置（显隐/置顶/卡片透明/卡片名称/调试日志）？[y/N] " ans
    case "${ans}" in y|Y|yes|YES) purge_settings=1 ;; esac
fi
if [ -n "${purge_settings}" ]; then
    if command -v dde-dconfig >/dev/null 2>&1; then
        echo "==> 清除面板设置（DConfig 用户覆盖）"
        for key in "${DCONFIG_KEYS[@]}"; do
            # 旧版本的配置描述文件可能没有该键、资源也可能缺失：失败只提示，不中断卸载。
            # 注意 reset 需要插件的配置描述文件仍在（本步骤因此排在删除文件之前）；
            # 若包已被 dpkg -r 清掉描述文件，重置必然失败、用户覆盖会留在守护进程库里，
            # 此时明确告知，别让用户以为已经清干净。
            if dde-dconfig reset -a "${DCONFIG_APPID}" -r "${PLUGIN_ID}" -k "${key}" >/dev/null 2>&1; then
                echo "  已重置 ${key}"
            elif [ ! -f "/usr/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json" ]; then
                echo "  跳过 ${key}（配置描述文件已不存在，用户覆盖仍留在 dde-dconfig 库中；重装后可在面板设置里手动改回默认）"
            else
                echo "  跳过 ${key}（配置项不存在或已是默认值）"
            fi
        done
        if [ "$(dde-dconfig get -a "${DCONFIG_APPID}" -r "${PLUGIN_ID}" -k cardTransparent -m isDefaultValue 2>/dev/null)" = "true" ]; then
            echo "  复查：cardTransparent 已回到默认值（关闭）"
        fi
    else
        echo "警告：未找到 dde-dconfig，跳过面板设置清理（可手动执行 dde-dconfig reset -a ${DCONFIG_APPID} -r ${PLUGIN_ID} -k <键名>）" >&2
    fi
else
    echo "保留面板设置（如需重置：dde-dconfig reset -a ${DCONFIG_APPID} -r ${PLUGIN_ID} -k cardTransparent）"
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
# 注：面板设置（DConfig 用户覆盖）已在上方单独确认并清理，且必须先于删除配置描述文件执行；
#     它的真实存储是 dde-dconfig 守护进程的按 uid 库，不在本步按路径删除。

echo "==> [4/4] 重启 dde-shell（卸载生效，托盘图标随之移除）"
systemctl --user restart dde-shell@DDE.service \
    || { echo "警告：dde-shell 重启失败，请手动执行：systemctl --user restart dde-shell@DDE" >&2; exit 1; }

echo
echo "卸载完成：插件文件、旧路径与缓存残留已清理，任务栏托盘图标已移除。"
echo "提示：若通过 .deb 安装过，请另行执行：sudo dpkg -r deepin-widget-toolbar"
