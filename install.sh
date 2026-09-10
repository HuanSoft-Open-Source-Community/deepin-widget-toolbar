#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# deepin-widget-toolbar 一键安装脚本：自动构建 -> 请求管理员权限部署 -> 让新增配置项生效 -> 重启 dde-shell。
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
META_PATH="/usr/share/dsg/configs/org.deepin.dde.shell/${PLUGIN_ID}.json"
# DConfig 应用 Id（面板代码里 DConfig::create 的第一个参数）
DCONFIG_APPID="org.deepin.dde.shell"

# 读取配置描述文件里的顶层配置项名（该文件由本项目维护，顶层键固定 8 空格缩进）
meta_keys() {
    sed -n 's/^        "\([^"]*\)": {.*/\1/p' "${META_PATH}" 2>/dev/null
}

if [ "$(id -u)" = "0" ]; then
    echo "错误：请以普通用户运行 ./install.sh（脚本内部会自动请求 sudo 密码，勿加 sudo）" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
cd "${REPO_ROOT}"

echo "==> [1/6] 检查构建环境"
for cmd in cmake sudo systemctl; do
    command -v "${cmd}" >/dev/null 2>&1 || { echo "错误：缺少命令 ${cmd}" >&2; exit 1; }
done

echo "==> [2/6] 构建插件（增量）"
# 幂等配置：无缓存则生成；已有缓存则校正安装前缀为 /usr
# （/usr/local 前缀的部署不被运行中的 dde-shell 搜索，会导致插件不生效）。
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
[ -f "build/plugins/${PLUGIN_ID}.so" ] || { echo "错误：构建产物缺失 build/plugins/${PLUGIN_ID}.so" >&2; exit 1; }
[ -f "build/tray/${TRAY_PLUGIN}" ] || { echo "错误：构建产物缺失 build/tray/${TRAY_PLUGIN}" >&2; exit 1; }

echo "==> [3/6] 部署到系统目录（请求管理员权限）"
sudo -v || { echo "错误：需要 sudo 权限安装到系统目录" >&2; exit 1; }
# 记录部署前的配置描述文件指纹，用于判断本次是否新增/变更了配置项
meta_before="$(sudo sha256sum "${META_PATH}" 2>/dev/null | awk '{print $1}' || true)"
sudo cmake --install build
meta_after="$(sha256sum "${META_PATH}" 2>/dev/null | awk '{print $1}' || true)"

echo "==> [4/6] 让新增/变更的配置项立即生效（dde-dconfig 守护进程）"
# 背景：dde-dconfig-daemon 只在启动时解析配置描述文件（实测 meta 更新后数小时仍未重解析），
# 所以升级后新增的配置项对 DConfig 是"不存在"的：读会走程序内兜底值（面板功能照常），
# 但**写会被拒绝** —— 用户在新开关上的改动当场生效、重启面板后却又回到默认，
# 看起来像"设置没保存"。这里在描述文件变化、或发现本插件有配置项尚未被守护进程识别时，
# 重启该服务使其重新解析（亚秒级，仅影响配置读写的一瞬）。
if [ -z "${meta_after}" ]; then
    echo "  警告：读不到 ${META_PATH}，跳过（请确认部署是否成功）" >&2
else
    need_restart=""
    if [ "${meta_before}" != "${meta_after}" ]; then
        need_restart="配置描述文件有变化"
        [ -n "${meta_before}" ] || need_restart="首次安装本插件的配置描述文件"
    elif command -v dde-dconfig >/dev/null 2>&1; then
        for key in $(meta_keys); do
            # 本插件的配置项都是布尔/字符串：取值非空即视为守护进程已知
            if [ -z "$(dde-dconfig get -a "${DCONFIG_APPID}" -r "${PLUGIN_ID}" -k "${key}" 2>/dev/null)" ]; then
                need_restart="配置项 ${key} 尚未被 dde-dconfig 识别（守护进程视图过期）"
                break
            fi
        done
    fi
    if [ -z "${need_restart}" ]; then
        echo "  配置项与守护进程视图一致，无需处理"
    else
        echo "  ${need_restart} → 重启 dde-dconfig-daemon 重新解析"
        sudo -v || true
        if sudo systemctl restart dde-dconfig-daemon.service; then
            for key in $(meta_keys); do
                if [ -z "$(dde-dconfig get -a "${DCONFIG_APPID}" -r "${PLUGIN_ID}" -k "${key}" 2>/dev/null)" ]; then
                    echo "  警告：配置项 ${key} 仍未被识别，请在重新登录后确认" >&2
                else
                    echo "  已识别 ${key}"
                fi
            done
        else
            echo "  警告：dde-dconfig-daemon 重启失败；新增配置项需等下次登录才会生效" >&2
        fi
    fi
fi

echo "==> [5/6] 清理不会生效的旧副本"
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

echo "==> [6/6] 重启 dde-shell（面板与托盘随其一并重载）"
# 托盘插件由 dde-shell 的 dock fork 出的 trayplugin-loader 进程加载，重启 dde-shell 即全部生效
systemctl --user restart dde-shell@DDE.service \
    || { echo "警告：dde-shell 重启失败，请手动执行：systemctl --user restart dde-shell@DDE" >&2; exit 1; }

echo
echo "安装完成："
echo "  面板 .so  → /usr/lib/x86_64-linux-gnu/dde-shell/${PLUGIN_ID}.so"
echo "  面板 QML  → /usr/share/dde-shell/${PLUGIN_ID}/"
echo "  托盘 .so  → /usr/lib/dde-dock/plugins/${TRAY_PLUGIN}"
echo "请在任务栏托盘区点击图标验证：左键显隐、右键菜单（添加/整理/设置/关于）。"
