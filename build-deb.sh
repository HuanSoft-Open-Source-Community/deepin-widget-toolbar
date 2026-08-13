#!/bin/bash
# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 构建 deepin-widget-toolbar 的 Debian 二进制包：
#   - 在临时副本中执行 dpkg-buildpackage，不污染工作区
#   - 产物拷贝到仓库根 dist/
#   - 只构建，不自动安装（postinst 会在安装时自动重启 dde-shell@DDE）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT

echo "==> Copying sources to ${BUILD_TMP}/src"
mkdir -p "${BUILD_TMP}/src"
tar --exclude='./.git' \
    --exclude='./build' \
    --exclude='./.tmp' \
    --exclude='./.reasonix' \
    --exclude='./dist' \
    --exclude='./debian/files' \
    --exclude='./debian/debhelper-build-stamp' \
    --exclude='./debian/*.debhelper*' \
    --exclude='./debian/*.substvars' \
    -cf - . | tar -xf - -C "${BUILD_TMP}/src"

echo "==> Building binary package (dpkg-buildpackage -b -us -uc)"
(
    cd "${BUILD_TMP}/src"
    dpkg-buildpackage -b -us -uc
)

mkdir -p dist
DEB_FILE="$(find "${BUILD_TMP}" -maxdepth 1 -name 'deepin-widget-toolbar_*.deb' -print -quit)"
if [ -z "$DEB_FILE" ]; then
    echo "ERROR: no .deb produced" >&2
    exit 1
fi

cp -v "$DEB_FILE" dist/
DEB_NAME="$(basename "$DEB_FILE")"

echo
echo "==> Built: dist/${DEB_NAME}"
echo "Install: sudo dpkg -i dist/${DEB_NAME}   (postinst restarts dde-shell@DDE)"
echo "Remove:  sudo dpkg -r deepin-widget-toolbar"
