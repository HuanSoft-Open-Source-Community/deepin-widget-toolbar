#!/bin/bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 构建 deepin-widget-toolbar 的 Debian 二进制包：
#   - 在临时副本中执行 dpkg-buildpackage，不污染工作区
#   - 产物拷贝到仓库根 dist/，完整构建日志写入 dist/build.log
#   - 只构建，不自动安装（postinst 会在安装时自动重启 dde-shell@DDE）
#
# 输出约定：控制台只显示阶段进度与结论。编译命令行、CMake/Qt 的探测输出等
# 全部进日志文件，构建期间只占一行显示百分比；只有构建真正失败时才打印日志
# 尾部。日志里 dpkg-shlibdeps 的 "diversions involved" 是本机 libc6 改道
# /lib64/ld-linux-x86-64.so.2 引起的环境提示，构建成功时会单独说明，不是打包错误。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="dist/build.log"

for tool in dpkg-buildpackage dh cmake tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: missing required tool: $tool" >&2
        exit 1
    fi
done

if [ ! -d debian ]; then
    echo "ERROR: debian/ directory not found" >&2
    exit 1
fi

if ! dpkg-checkbuilddeps >/dev/null 2>&1; then
    echo "ERROR: missing build dependencies:" >&2
    dpkg-checkbuilddeps >&2 || true
    echo "Install them with: sudo apt install <listed packages>" >&2
    exit 1
fi

# 版本自检：应用版本来自 CMake 工程版本（关于对话框由 Panel.appVersion 读它，
# 不再手写），包版本由 debian/changelog 决定；两处不一致时只提示、不阻断构建。
APP_VERSION="$(sed -n 's/^project([^)]*VERSION[[:space:]]\+\([^ )]*\).*/\1/p' CMakeLists.txt | head -n 1)"
PKG_VERSION="$(dpkg-parsechangelog -SVersion 2>/dev/null | head -n 1 || true)"
PKG_UPSTREAM="${PKG_VERSION%-*}" # 3.0 (native) 不允许带 -修订号，比对前先剥掉

if [ -n "${PKG_VERSION}" ] && [ "${PKG_VERSION}" != "${PKG_UPSTREAM}" ]; then
    echo "WARNING: debian/source/format is 3.0 (native), so the package version must not carry" >&2
    echo "         a Debian revision (now ${PKG_VERSION}): building a source package would fail" >&2
    echo "         with \"native package version may not have a revision\"." >&2
fi
if [ -n "${PKG_UPSTREAM}" ] && [ -n "${APP_VERSION}" ] && [ "${PKG_UPSTREAM}" != "${APP_VERSION}" ]; then
    echo "WARNING: package version (debian/changelog) is ${PKG_UPSTREAM} but the app version" >&2
    echo "         (CMakeLists.txt) is ${APP_VERSION}." >&2
fi
# 关于对话框必须继续从宿主读版本；若被改回手写常量，这里立刻提醒
if ! grep -q 'Panel\.appVersion' panel/package/AboutPopup.qml; then
    echo "WARNING: AboutPopup.qml no longer reads Panel.appVersion; the about dialog may show" >&2
    echo "         a version that drifts from CMakeLists.txt (project VERSION ${APP_VERSION})." >&2
fi

BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT

mkdir -p dist

echo "==> Copying sources to ${BUILD_TMP}/src"
mkdir -p "${BUILD_TMP}/src"
tar --exclude='./.git' \
    --exclude='./build' \
    --exclude='./build-tests' \
    --exclude='./CMakeFiles' \
    --exclude='./obj-*' \
    --exclude='./.tmp' \
    --exclude='./.reasonix' \
    --exclude='./dist' \
    --exclude='./debian/files' \
    --exclude='./debian/debhelper-build-stamp' \
    --exclude='./debian/*.debhelper*' \
    --exclude='./debian/*.substvars' \
    --exclude='./debian/deepin-widget-toolbar' \
    -cf - . | tar -xf - -C "${BUILD_TMP}/src"

echo "==> Building the binary package (dpkg-buildpackage -b -us -uc)"
echo "    full log: ${LOG_FILE}"
build_status=0
(
    cd "${BUILD_TMP}/src"
    exec dpkg-buildpackage -b -us -uc
) >"$LOG_FILE" 2>&1 &
build_pid=$!

# 构建期间只占一行显示进度百分比：既不刷屏，也不至于长时间没有任何输出。
# 输出被重定向到文件时（非终端）不打进度，避免 \r 在文件里堆成一串。
show_progress=0
if [ -t 1 ]; then
    show_progress=1
fi
while kill -0 "$build_pid" 2>/dev/null; do
    if [ "$show_progress" -eq 1 ]; then
        progress="$(grep -aoE '^\[ *[0-9]+%\]' "$LOG_FILE" 2>/dev/null | tail -n 1 || true)"
        printf '\r    %-24s' "${progress:-working...}"
    fi
    sleep 1
done
wait "$build_pid" || build_status=$?
if [ "$show_progress" -eq 1 ]; then
    printf '\r%*s\r' 24 ''
fi

if [ "$build_status" -ne 0 ]; then
    echo "ERROR: dpkg-buildpackage failed (exit ${build_status})." >&2
    echo "Diagnostics from ${LOG_FILE}:" >&2
    # 只挑真正的报错行（CMake 报错连同正文、编译器/dh/dpkg 的 error:、make *** ）；
    # 失败时 CMake 会把整个 CMakeCache 转储到日志尾部，那对定位问题没有帮助。
    diagnostics="$(grep -aA1 -E '^CMake Error|error: |errors? generated|undefined reference|collect2: |^make(\[[0-9]+\])?: \*\*\*' "$LOG_FILE" 2>/dev/null | tail -n 24 || true)"
    if [ -n "$diagnostics" ]; then
        echo "$diagnostics" >&2
    else
        tail -n 20 "$LOG_FILE" >&2
    fi
    echo "Full log kept at: ${LOG_FILE}" >&2
    exit "$build_status"
fi

DEB_FILE="$(find "${BUILD_TMP}" -maxdepth 1 -name 'deepin-widget-toolbar_*.deb' -print -quit)"
if [ -z "$DEB_FILE" ]; then
    echo "ERROR: no .deb produced; see ${LOG_FILE}" >&2
    exit 1
fi

DEB_NAME="$(basename "$DEB_FILE")"
cp "$DEB_FILE" dist/
DIST_DEB="dist/${DEB_NAME}"
DEB_VERSION="$(dpkg-deb -f "$DIST_DEB" Version 2>/dev/null || echo unknown)"
DEB_ARCH="$(dpkg-deb -f "$DIST_DEB" Architecture 2>/dev/null || echo unknown)"
DEB_SIZE="$(du -h "$DIST_DEB" | cut -f 1)"

echo
echo "==> Built: ${DIST_DEB}"
echo "    package: deepin-widget-toolbar ${DEB_VERSION} (${DEB_ARCH}, ${DEB_SIZE})"
echo "    log:     ${LOG_FILE}"
if grep -q 'dpkg-shlibdeps: warning: diversions involved' "$LOG_FILE" 2>/dev/null; then
    echo "    note:    the log mentions dpkg-shlibdeps' \"diversions involved\": this system diverts"
    echo "             /lib64/ld-linux-x86-64.so.2, so it is an environment notice, not a build error."
fi
echo "Install: sudo dpkg -i ${DIST_DEB}   (postinst restarts dde-shell@DDE)"
echo "Remove:  sudo dpkg -r deepin-widget-toolbar"
