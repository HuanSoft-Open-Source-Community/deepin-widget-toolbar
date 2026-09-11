# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

# DSG 元数据安装目录由顶层 CMakeLists.txt 固定为 /usr/share/dsg，
# 与 dde-shell 运行时 DConfig 搜索路径一致；不随 CMAKE_INSTALL_PREFIX 漂移

find_package(Dtk6DConfig REQUIRED)
find_package(Qt6 COMPONENTS LinguistTools Qml DBus Concurrent REQUIRED)

add_library(ds-widget-toolbar SHARED
    debuglogger.cpp
    debuglogger.h
    widgettoolbarpanel.cpp
    widgettoolbarpanel.h
    widgetmanager.cpp
    widgetmanager.h
    widgettypes.h
    widgetgrid.cpp
    widgetgrid.h
    widgetpackage.cpp
    widgetpackage.h
    widgetschema.cpp
    widgetschema.h
    sysfsreader.cpp
    sysfsreader.h
    nvmlhelper.cpp
    nvmlhelper.h
    gpuhelper.cpp
    gpuhelper.h
    npuhelper.cpp
    npuhelper.h
    timezonedb.cpp
    timezonedb.h
    windowguard.cpp
    windowguard.h
    panelavoidwatcher.cpp
    panelavoidwatcher.h
    mprisparsing.cpp
    mprisparsing.h
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
    desktopapps.cpp
    desktopapps.h
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

# xcb：WindowGuard 在 X11 下直接以 xcb_change_property 恢复窗口类型
# （_NET_WM_WINDOW_TYPE），防止 kwin 把面板当普通窗口垂直最大化
find_package(XCB REQUIRED)
# 调试日志（debuglogger.cpp）刻意只用 Qt 自带的 QFile/QTextStream，不链 Dtk6::Log：
# DTK6 的 RollingFileAppender 只按时间频率或字节大小轮转，给不出"单文件 2500 行"
# 这个硬要求；且 Logger::globalInstance() 是进程级单例，本面板跑在 dde-shell 进程内，
# appender 注册/注销稍有疏漏就会悬垂并拖崩整个 shell。
target_link_libraries(ds-widget-toolbar PRIVATE Dde::Shell Qt6::Qml Qt6::DBus Qt6::Concurrent m XCB::XCB)

# PipeWire 后端的 SPA POD 使用官方 inline builder（仅需头文件，无链接依赖）；
# 头文件缺失时回退手写 POD（pipewirebackend.cpp 内 HAVE_SPA_POD_BUILDER=0）
find_path(SPA_INCLUDE_DIR spa/pod/builder.h HINTS /usr/include/spa-0.2)
if(SPA_INCLUDE_DIR)
    target_include_directories(ds-widget-toolbar PRIVATE ${SPA_INCLUDE_DIR})
    target_compile_definitions(ds-widget-toolbar PRIVATE HAVE_SPA_POD_BUILDER=1)
endif()

dtk_add_config_meta_files(APPID "org.deepin.dde.shell" FILES configs/org.deepin.ds.widgettoolbar.json)

# 应用版本单一来源：把工程的 PROJECT_VERSION 编译进来，关于对话框由
# Panel.appVersion 读取，不再在 QML 里手写常量（此前三处版本号靠人工同步，
# 漏改只能靠 build-deb.sh 的自检事后提醒）。
target_compile_definitions(ds-widget-toolbar PRIVATE WIDGETTOOLBAR_VERSION="${PROJECT_VERSION}")

ds_install_package(PACKAGE org.deepin.ds.widgettoolbar TARGET ds-widget-toolbar)
ds_handle_package_translation(PACKAGE org.deepin.ds.widgettoolbar)
