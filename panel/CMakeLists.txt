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
    mediaplayer.cpp
    mediaplayer.h
    mediaplayerregistry.cpp
    mediaplayerregistry.h
    systeminfo.cpp
    systeminfo.h
    systeminfoworker.cpp
    systeminfoworker.h
    timezones.cpp
    timezones.h
    widgethost.cpp
    widgethost.h
    audiovisualizer.cpp
    audiovisualizer.h
    spectrumcapture.cpp
    spectrumcapture.h
    audiobackend.h
    pulsebackend.cpp
    pulsebackend.h
    pipewirebackend.cpp
    pipewirebackend.h
    alsabackend.cpp
    alsabackend.h
    widgetresources.qrc
)

target_link_libraries(ds-widget-toolbar PRIVATE Dde::Shell Qt6::Qml Qt6::DBus Qt6::Concurrent m)

# PipeWire 后端的 SPA POD 使用官方 inline builder（仅需头文件，无链接依赖）；
# 头文件缺失时回退手写 POD（pipewirebackend.cpp 内 HAVE_SPA_POD_BUILDER=0）
find_path(SPA_INCLUDE_DIR spa/pod/builder.h HINTS /usr/include/spa-0.2)
if(SPA_INCLUDE_DIR)
    target_include_directories(ds-widget-toolbar PRIVATE ${SPA_INCLUDE_DIR})
    target_compile_definitions(ds-widget-toolbar PRIVATE HAVE_SPA_POD_BUILDER=1)
endif()

dtk_add_config_meta_files(APPID "org.deepin.dde.shell" FILES configs/org.deepin.ds.widgettoolbar.json)

ds_install_package(PACKAGE org.deepin.ds.widgettoolbar TARGET ds-widget-toolbar)
ds_handle_package_translation(PACKAGE org.deepin.ds.widgettoolbar)
