# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus LinguistTools)
find_package(Dtk6Widget REQUIRED)
find_package(Dtk6Gui REQUIRED)

set(PLUGIN_NAME "widget-toolbar")

add_library(${PLUGIN_NAME} SHARED
    widgettoolbartrayplugin.cpp
    widgettoolbartrayplugin.h
    traybutton.cpp
    traybutton.h
    icons/icons.qrc
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE QT_PLUGIN)

target_include_directories(${PLUGIN_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/interfaces
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::DBus
    Dtk6::Widget
    Dtk6::Gui
)

# 翻译：lupdate 扫描 C++ tr() 更新 .ts，lrelease 生成 .qm
file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/translations")
qt_add_translations(${PLUGIN_NAME}
    TS_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/translations/widget-toolbar_en.ts"
        "${CMAKE_CURRENT_SOURCE_DIR}/translations/widget-toolbar_zh_CN.ts"
    QM_FILES_OUTPUT_VARIABLE widget_toolbar_qm_files
)

install(TARGETS ${PLUGIN_NAME} LIBRARY DESTINATION /usr/lib/dde-dock/plugins)
install(FILES ${widget_toolbar_qm_files} DESTINATION /usr/share/widget-toolbar/translations)
