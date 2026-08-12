# SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: GPL-3.0-or-later

find_package(Dtk6DConfig REQUIRED)
find_package(Qt6 COMPONENTS LinguistTools REQUIRED)

add_library(ds-widget-toolbar SHARED
    widgettoolbarpanel.cpp
    widgettoolbarpanel.h
)

target_link_libraries(ds-widget-toolbar PRIVATE Dde::Shell)

dtk_add_config_meta_files(APPID "org.deepin.dde.shell" FILES configs/org.deepin.ds.widgettoolbar.json)

ds_install_package(PACKAGE org.deepin.ds.widgettoolbar TARGET ds-widget-toolbar)
ds_handle_package_translation(PACKAGE org.deepin.ds.widgettoolbar)
