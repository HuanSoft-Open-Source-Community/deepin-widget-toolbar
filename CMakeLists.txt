# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.13)
project(deepin-widget-toolbar VERSION 0.1.1.0 LANGUAGES CXX)

# debhelper 的 cmake 构建系统会自动注入这些开关；显式引用它们，
# 避免在 Debian 构建时出现 "Manually-specified variables were not used" 警告。
set(_DEBHELPER_CMAKE_SWITCHES
    "${CMAKE_EXPORT_NO_PACKAGE_REGISTRY}"
    "${CMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY}"
    "${FETCHCONTENT_FULLY_DISCONNECTED}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# DSG 元数据固定使用系统标准位置（/usr/share/dsg），
# 需在 Dtk6DConfig 首次被 find_package 加载前设置，
# 否则其 add_definitions 会按默认安装前缀生成 /usr/local/share/dsg 的重复定义
set(DSG_DATA_DIR "/usr/share/dsg" CACHE STRING "DSG metadata directory" FORCE)

find_package(DDEShell REQUIRED)

add_subdirectory(panel)
add_subdirectory(tray)

# PanelAvoidWatcher 回归测试（直接编译 watcher 源文件，需 X11 会话运行；
# 非 xcb 平台用例自跳过）。默认关闭：配置时 -DWIDGETTOOLBAR_BUILD_TESTS=ON。
option(WIDGETTOOLBAR_BUILD_TESTS "Build the PanelAvoidWatcher regression tests" OFF)
if(WIDGETTOOLBAR_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests/panelavoidwatcher)
endif()
