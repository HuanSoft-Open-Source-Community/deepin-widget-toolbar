# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

# DSG 元数据安装目录由顶层 CMakeLists.txt 固定为 /usr/share/dsg，
# 与 dde-shell 运行时 DConfig 搜索路径一致；不随 CMAKE_INSTALL_PREFIX 漂移

find_package(Dtk6DConfig REQUIRED)
find_package(Qt6 COMPONENTS LinguistTools Qml DBus Concurrent REQUIRED)

add_library(ds-widget-toolbar SHARED
    widgettoolbarpanel.cpp
    widgettoolbarpanel.h
    widgetmanager.cpp
    widgetmanager.h
    widgetmodel.cpp
    widgetmodel.h
    fileio.cpp
    fileio.h
    clocktime.cpp
    clocktime.h
    lyricssource.cpp
    lyricssource.h
    systeminfo.cpp
    systeminfo.h
    systeminfoworker.cpp
    systeminfoworker.h
    timezones.cpp
    timezones.h
    widgethost.cpp
    widgethost.h
    widgetresources.qrc
)

target_link_libraries(ds-widget-toolbar PRIVATE Dde::Shell Qt6::Qml Qt6::DBus Qt6::Concurrent)

dtk_add_config_meta_files(APPID "org.deepin.dde.shell" FILES configs/org.deepin.ds.widgettoolbar.json)

ds_install_package(PACKAGE org.deepin.ds.widgettoolbar TARGET ds-widget-toolbar)
ds_handle_package_translation(PACKAGE org.deepin.ds.widgettoolbar)
