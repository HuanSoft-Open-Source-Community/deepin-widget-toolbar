// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "nvmlhelper.h"
#include "sysfsreader.h"

#include <QHash>
#include <QString>

// GPU 利用率采样器：依次尝试 NVML → sysfs 百分比 → Intel Xe 累积 idle，
// 首次定位后缓存来源路径，按固定间隔重扫描。
class GpuHelper
{
public:
    // 读缓存来源的当前利用率；来源失效返回 false（调用方按间隔重扫描）
    bool read(qreal *usage);
    // 按重扫描间隔重新定位来源；定位成功返回 true 并输出利用率
    bool scanIfDue(qreal *usage);
    bool available() const { return m_source != Source::None; }

private:
    enum class Source { None, Nvml, PercentPath, XeIdlePath };

    bool scan(qreal *usage);

    Source m_source = Source::None;
    QString m_path;
    qint64 m_lastScanUs = 0;
    QHash<QString, SysfsReader::CumulativeSample> m_samples;
    NvmlHelper m_nvml;
};
