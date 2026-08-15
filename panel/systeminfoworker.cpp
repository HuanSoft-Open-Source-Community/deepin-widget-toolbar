// SPDX-FileCopyrightText: 2025 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "systeminfoworker.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLibrary>
#include <QStorageInfo>

#include <unistd.h>

#include <chrono>

namespace {

constexpr qint64 kSourceRescanIntervalUs = 30LL * 1000 * 1000;

qint64 nowUs()
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

qreal clampFraction(qreal value)
{
    return qBound<qreal>(0.0, value, 1.0);
}

bool readFirstNumber(const QString &path, quint64 *out)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    bool ok = false;
    const quint64 value = f.readLine().trimmed().toULongLong(&ok);
    if (ok)
        *out = value;
    return ok;
}

bool readFirstLine(const QString &path, QByteArray *out)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    *out = f.readLine().trimmed();
    return true;
}

QStringList listSysfsDevices(const QString &dirPath, const QString &prefix)
{
    QStringList result;
    const QDir dir(dirPath);
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        if (entry.startsWith(prefix) && QFileInfo(dirPath + QLatin1Char('/') + entry).isDir())
            result.append(dirPath + QLatin1Char('/') + entry);
    }
    return result;
}

QString readTextFile(const QString &path)
{
    QByteArray line;
    return readFirstLine(path, &line) ? QString::fromUtf8(line) : QString();
}

bool readPercentFile(const QString &path, qreal *out)
{
    quint64 value = 0;
    if (!readFirstNumber(path, &value))
        return false;
    *out = clampFraction(qreal(value) / 100.0);
    return true;
}

// ===== NVIDIA NVML（运行时动态加载，无编译期依赖） =====
struct NvmlUtilization {
    unsigned int gpu = 0;
    unsigned int memory = 0;
};
using NvmlReturn = int;
using NvmlDevice = void *;
using NvmlInitFn = NvmlReturn (*)();
using NvmlShutdownFn = NvmlReturn (*)();
using NvmlDeviceGetCountFn = NvmlReturn (*)(unsigned int *);
using NvmlDeviceGetHandleByIndexFn = NvmlReturn (*)(unsigned int, NvmlDevice *);
using NvmlDeviceGetUtilizationRatesFn = NvmlReturn (*)(NvmlDevice, NvmlUtilization *);

struct NvmlApi {
    QLibrary library;
    NvmlInitFn init = nullptr;
    NvmlShutdownFn shutdown = nullptr;
    NvmlDeviceGetCountFn deviceGetCount = nullptr;
    NvmlDeviceGetHandleByIndexFn deviceGetHandleByIndex = nullptr;
    NvmlDeviceGetUtilizationRatesFn deviceGetUtilizationRates = nullptr;
};

bool loadNvmlApi(NvmlApi *api)
{
    if (api->library.isLoaded())
        return true;

    api->library.setFileName(QStringLiteral("nvidia-ml.so.1"));
    if (!api->library.load())
        api->library.setFileName(QStringLiteral("nvidia-ml"));
    if (!api->library.isLoaded() && !api->library.load())
        return false;

    api->init = reinterpret_cast<NvmlInitFn>(api->library.resolve("nvmlInit_v2"));
    api->shutdown = reinterpret_cast<NvmlShutdownFn>(api->library.resolve("nvmlShutdown"));
    api->deviceGetCount = reinterpret_cast<NvmlDeviceGetCountFn>(api->library.resolve("nvmlDeviceGetCount_v2"));
    api->deviceGetHandleByIndex = reinterpret_cast<NvmlDeviceGetHandleByIndexFn>(
        api->library.resolve("nvmlDeviceGetHandleByIndex_v2"));
    if (!api->deviceGetHandleByIndex) {
        api->deviceGetHandleByIndex = reinterpret_cast<NvmlDeviceGetHandleByIndexFn>(
            api->library.resolve("nvmlDeviceGetHandleByIndex"));
    }
    api->deviceGetUtilizationRates = reinterpret_cast<NvmlDeviceGetUtilizationRatesFn>(
        api->library.resolve("nvmlDeviceGetUtilizationRates"));

    return api->init && api->shutdown && api->deviceGetCount
        && api->deviceGetHandleByIndex && api->deviceGetUtilizationRates;
}

bool readNvmlGpuUsage(qreal *out)
{
    static NvmlApi api;
    static bool initAttempted = false;
    static bool available = false;

    if (!initAttempted) {
        initAttempted = true;
        if (loadNvmlApi(&api) && api.init() == 0)
            available = true;
    }
    if (!available)
        return false;

    unsigned int count = 0;
    if (api.deviceGetCount(&count) != 0 || count == 0)
        return false;

    unsigned int best = 0;
    for (unsigned int i = 0; i < count; ++i) {
        NvmlDevice device = nullptr;
        NvmlUtilization utilization;
        if (api.deviceGetHandleByIndex(i, &device) != 0)
            continue;
        if (api.deviceGetUtilizationRates(device, &utilization) != 0)
            continue;
        best = qMax(best, utilization.gpu);
    }
    *out = clampFraction(qreal(best) / 100.0);
    return true;
}

bool gpuPercentCandidates(const QString &card, QStringList *paths)
{
    const QString vendor = readTextFile(card + QStringLiteral("/device/vendor"));
    paths->clear();
    if (vendor == QLatin1String("0x8086")) {
        paths->append(card + QStringLiteral("/gt/gt0/gt_busy_percent"));
        paths->append(card + QStringLiteral("/device/gt/gt0/gt_busy_percent"));
        paths->append(card + QStringLiteral("/gt/gt0/media_busy_percent"));
        paths->append(card + QStringLiteral("/device/gt/gt0/media_busy_percent"));
    }
    paths->append(card + QStringLiteral("/gpu_busy_percent"));
    paths->append(card + QStringLiteral("/device/gpu_busy_percent"));
    return vendor == QLatin1String("0x8086");
}

QStringList hwmonBusyCandidates(const QString &card)
{
    QStringList result;
    const QString hwmonRoot = card + QStringLiteral("/device/hwmon");
    const QStringList hwmons = listSysfsDevices(hwmonRoot, QStringLiteral("hwmon"));
    for (const QString &hwmon : hwmons)
        result.append(hwmon + QStringLiteral("/busy"));
    return result;
}

QStringList xeIdleCandidates(const QString &card)
{
    return {
        card + QStringLiteral("/device/tile0/gt0/gtidle/idle_residency_ms"),
        card + QStringLiteral("/device/gt0/gtidle/idle_residency_ms"),
        card + QStringLiteral("/gt/gt0/gtidle/idle_residency_ms"),
    };
}

bool updateBusyFromIdleMs(const QString &path,
                          QHash<QString, SystemInfoWorker::CumulativeSample> *samples,
                          qreal *busy)
{
    quint64 idleMs = 0;
    if (!readFirstNumber(path, &idleMs))
        return false;

    const qint64 now = nowUs();
    auto it = samples->find(path);
    if (it == samples->end()) {
        samples->insert(path, {idleMs, now});
        return false;
    }
    const qint64 dtUs = now - it->timeUs;
    const quint64 dIdleMs = idleMs >= it->value ? idleMs - it->value : 0;
    it->value = idleMs;
    it->timeUs = now;
    if (dtUs <= 0)
        return false;

    // idle_residency_ms 为累积毫秒：busy = 1 - Δidle/Δtime。
    const qreal idleFraction = qreal(dIdleMs) / (qreal(dtUs) / 1000.0);
    *busy = clampFraction(1.0 - idleFraction);
    return true;
}

QString accelDriverName(const QString &device)
{
    const QFileInfo link(device + QStringLiteral("/device/driver"));
    if (link.exists())
        return QFileInfo(link.symLinkTarget()).fileName();
    return QString();
}

bool updateUsageFromBusyUs(const QString &path,
                           QHash<QString, SystemInfoWorker::CumulativeSample> *samples,
                           qreal *usage)
{
    quint64 busyUs = 0;
    if (!readFirstNumber(path, &busyUs))
        return false;

    const qint64 now = nowUs();
    auto it = samples->find(path);
    if (it == samples->end()) {
        samples->insert(path, {busyUs, now});
        return false;
    }
    const qint64 dtUs = now - it->timeUs;
    const quint64 dBusyUs = busyUs >= it->value ? busyUs - it->value : 0;
    it->value = busyUs;
    it->timeUs = now;
    if (dtUs <= 0)
        return false;

    *usage = clampFraction(qreal(dBusyUs) / qreal(dtUs));
    return true;
}

} // namespace

SystemInfoWorker::SystemInfoWorker(QObject *parent)
    : QObject(parent)
{
}

bool SystemInfoWorker::metricEnabled(const QString &metricId) const
{
    return m_metrics.contains(metricId);
}

void SystemInfoWorker::setState(bool active, const QStringList &metrics,
                                int intervalMs)
{
    // setState 经 QueuedConnection 只在工作线程执行：首次调用时把定时器
    // 创建在当前线程，确保定时器与采样循环线程亲和性一致。
    if (!m_timer) {
        m_timer = new QTimer(this);
        m_timer->setTimerType(Qt::CoarseTimer);
        connect(m_timer, &QTimer::timeout, this, &SystemInfoWorker::sample);
    }

    m_active = active;
    m_metrics.clear();
    for (const QString &metric : metrics) {
        const QString normalized = metric.trimmed().toLower();
        if (!normalized.isEmpty())
            m_metrics.insert(normalized);
    }

    m_timer->setInterval(qMax(1000, intervalMs));

    if (!m_active || m_metrics.isEmpty()) {
        m_timer->stop();
        return;
    }

    sample();
    if (!m_timer->isActive())
        m_timer->start();
}

void SystemInfoWorker::sample()
{
    if (!m_active || m_metrics.isEmpty())
        return;

    if (metricEnabled(QStringLiteral("cpu")))
        readCpu();
    if (metricEnabled(QStringLiteral("mem")))
        readMem();
    if (metricEnabled(QStringLiteral("diskUsed")))
        readDisk();
    if (metricEnabled(QStringLiteral("disk")))
        readDiskIO();
    if (metricEnabled(QStringLiteral("gpu")))
        readGpu();
    if (metricEnabled(QStringLiteral("npu")))
        readNpu();

    Q_EMIT sampleReady(m_cpuUsage, m_memUsedPercent, m_diskUsedPercent,
                       m_diskBusyPercent, m_gpuUsage, m_gpuAvailable,
                       m_npuUsage, m_npuAvailable);
}

void SystemInfoWorker::readCpu()
{
    // /proc/stat 第一行 "cpu  user nice system idle iowait irq softirq steal ..."
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QByteArray line = f.readLine();
    QList<quint64> vals;
    const QStringList parts = QString::fromUtf8(line).split(' ', Qt::SkipEmptyParts);
    for (const QString &p : parts) {
        bool ok = false;
        const quint64 v = p.toULongLong(&ok);
        if (ok)
            vals.append(v);
    }
    if (vals.size() < 4)
        return;

    quint64 idle = vals.at(3);   // idle
    if (vals.size() > 4)
        idle += vals.at(4);      // iowait
    quint64 total = 0;
    for (quint64 v : vals)
        total += v;

    if (m_prevTotal != 0) {
        const quint64 dTotal = total - m_prevTotal;
        const quint64 dIdle = idle - m_prevIdle;
        if (dTotal > 0)
            m_cpuUsage = clampFraction(1.0 - qreal(dIdle) / qreal(dTotal));
    }
    m_prevTotal = total;
    m_prevIdle = idle;
}

void SystemInfoWorker::readMem()
{
    QFile f("/proc/meminfo");
    if (!f.open(QIODevice::ReadOnly))
        return;

    quint64 total = 0;
    quint64 available = 0;
    const QStringList lines = QString::fromUtf8(f.readAll()).split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QStringList parts = line.simplified().split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 2)
            continue;
        if (parts.at(0) == QLatin1String("MemTotal:")) {
            total = parts.at(1).toULongLong();
        } else if (parts.at(0) == QLatin1String("MemAvailable:")) {
            available = parts.at(1).toULongLong();
        }
        if (total > 0 && available > 0)
            break;
    }
    if (total > 0)
        m_memUsedPercent = clampFraction(1.0 - qreal(available) / qreal(total));
}

void SystemInfoWorker::readDisk()
{
    // 根分区占用：保留给旧接口，资源监视面板不再展示此项。
    const QStorageInfo root("/");
    if (root.isValid() && root.bytesTotal() > 0) {
        const qreal used = qreal(root.bytesTotal() - root.bytesAvailable());
        m_diskUsedPercent = clampFraction(used / qreal(root.bytesTotal()));
    }
}

void SystemInfoWorker::refreshDiskDevices()
{
    m_diskDevices.clear();
    QFile f("/proc/diskstats");
    if (!f.open(QIODevice::ReadOnly))
        return;

    static const QStringList prefixes = {
        QStringLiteral("nvme"), QStringLiteral("sd"), QStringLiteral("mmcblk"),
        QStringLiteral("vd"), QStringLiteral("xvd"),
    };
    while (!f.atEnd()) {
        const QStringList parts = QString::fromUtf8(f.readLine())
                                      .simplified()
                                      .split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 3)
            continue;
        const QString name = parts.at(2);
        bool physical = false;
        for (const QString &prefix : prefixes) {
            if (name.startsWith(prefix)) {
                physical = true;
                break;
            }
        }
        if (!physical)
            continue;
        if (QFileInfo::exists(QStringLiteral("/sys/class/block/") + name
                              + QStringLiteral("/partition"))) {
            continue;
        }
        m_diskDevices.insert(name);
    }
    m_diskDevicesRefreshedUs = nowUs();
}

void SystemInfoWorker::readDiskIO()
{
    if (m_clockTicksPerSecond <= 0) {
        m_clockTicksPerSecond = sysconf(_SC_CLK_TCK);
        if (m_clockTicksPerSecond <= 0)
            m_clockTicksPerSecond = 100;
    }

    const qint64 now = nowUs();
    if (m_diskDevices.isEmpty() || now - m_diskDevicesRefreshedUs > kSourceRescanIntervalUs)
        refreshDiskDevices();

    QFile f("/proc/diskstats");
    if (!f.open(QIODevice::ReadOnly))
        return;

    quint64 busyTicks = 0;
    while (!f.atEnd()) {
        const QStringList parts = QString::fromUtf8(f.readLine())
                                      .simplified()
                                      .split(' ', Qt::SkipEmptyParts);
        if (parts.size() < 13)
            continue;
        if (!m_diskDevices.contains(parts.at(2)))
            continue;
        busyTicks += parts.at(12).toULongLong();
    }

    if (m_prevDiskTimeUs > 0 && now > m_prevDiskTimeUs) {
        const quint64 deltaTicks = busyTicks >= m_prevDiskBusyTicks
            ? busyTicks - m_prevDiskBusyTicks : 0;
        const qreal elapsedSeconds = qreal(now - m_prevDiskTimeUs) / 1000000.0;
        const qreal busySeconds = qreal(deltaTicks) / qreal(m_clockTicksPerSecond);
        m_diskBusyPercent = clampFraction(busySeconds / elapsedSeconds);
    } else {
        m_diskBusyPercent = 0.0;
    }
    m_prevDiskBusyTicks = busyTicks;
    m_prevDiskTimeUs = now;
}

bool SystemInfoWorker::readCachedGpu()
{
    qreal value = 0.0;
    switch (m_gpuSource) {
    case GpuSource::Nvml:
        if (readNvmlGpuUsage(&value)) {
            m_gpuUsage = value;
            m_gpuAvailable = true;
            return true;
        }
        break;
    case GpuSource::PercentPath:
        if (readPercentFile(m_gpuPath, &value)) {
            m_gpuUsage = value;
            m_gpuAvailable = true;
            return true;
        }
        break;
    case GpuSource::XeIdlePath:
        if (updateBusyFromIdleMs(m_gpuPath, &m_cumulativeSamples, &value)) {
            m_gpuUsage = value;
            m_gpuAvailable = true;
            return true;
        }
        // 首次采样仅建立基线，保持已定位的累积路径，下一周期再计算。
        return false;
    case GpuSource::None:
        return false;
    }

    m_gpuSource = GpuSource::None;
    m_gpuPath.clear();
    m_gpuLastScanUs = 0;
    return false;
}

bool SystemInfoWorker::scanGpu()
{
    qreal nvmlUsage = 0.0;
    if (readNvmlGpuUsage(&nvmlUsage)) {
        m_gpuSource = GpuSource::Nvml;
        m_gpuUsage = nvmlUsage;
        m_gpuAvailable = true;
        return true;
    }

    qreal best = 0.0;
    bool found = false;
    const QStringList cards = listSysfsDevices(QStringLiteral("/sys/class/drm"), QStringLiteral("card"));
    for (const QString &card : cards) {
        QStringList percentPaths;
        const bool intel = gpuPercentCandidates(card, &percentPaths);
        bool hasPercent = false;
        for (const QString &path : percentPaths) {
            qreal value = 0.0;
            if (readPercentFile(path, &value)) {
                best = qMax(best, value);
                found = true;
                hasPercent = true;
                m_gpuSource = GpuSource::PercentPath;
                m_gpuPath = path;
                break;
            }
        }

        // AMD 无 gpu_busy_percent 时按调研回退 hwmon/busy。
        if (!hasPercent && !intel) {
            for (const QString &path : hwmonBusyCandidates(card)) {
                qreal value = 0.0;
                if (readPercentFile(path, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_gpuSource = GpuSource::PercentPath;
                    m_gpuPath = path;
                    break;
                }
            }
        }

        // Intel Xe 没有标准 busy_percent，改用 idle_residency_ms 累积差值。
        if (intel && !hasPercent) {
            for (const QString &path : xeIdleCandidates(card)) {
                qreal value = 0.0;
                if (updateBusyFromIdleMs(path, &m_cumulativeSamples, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_gpuSource = GpuSource::XeIdlePath;
                    m_gpuPath = path;
                    break;
                }
                // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
                if (QFileInfo::exists(path)) {
                    m_gpuSource = GpuSource::XeIdlePath;
                    m_gpuPath = path;
                    break;
                }
            }
        }
        if (found)
            break;
    }

    if (found) {
        m_gpuUsage = best;
        m_gpuAvailable = true;
    }
    return found;
}

void SystemInfoWorker::readGpu()
{
    m_gpuUsage = 0.0;
    m_gpuAvailable = false;

    if (readCachedGpu())
        return;

    const qint64 now = nowUs();
    if (m_gpuLastScanUs == 0 || now - m_gpuLastScanUs >= kSourceRescanIntervalUs) {
        m_gpuLastScanUs = now;
        scanGpu();
    }
}

bool SystemInfoWorker::readCachedNpu()
{
    qreal value = 0.0;
    switch (m_npuSource) {
    case NpuSource::PercentPath:
        if (readPercentFile(m_npuPath, &value)) {
            m_npuUsage = value;
            m_npuAvailable = true;
            return true;
        }
        break;
    case NpuSource::CumulativePath:
        if (updateUsageFromBusyUs(m_npuPath, &m_cumulativeSamples, &value)) {
            m_npuUsage = value;
            m_npuAvailable = true;
            return true;
        }
        // 首次采样仅建立基线，保持已定位的累积路径，下一周期再计算。
        return false;
    case NpuSource::None:
        return false;
    }

    m_npuSource = NpuSource::None;
    m_npuPath.clear();
    m_npuLastScanUs = 0;
    return false;
}

bool SystemInfoWorker::scanNpu()
{
    qreal best = 0.0;
    bool found = false;
    const QStringList devices = listSysfsDevices(QStringLiteral("/sys/class/accel"), QStringLiteral("accel"));
    for (const QString &device : devices) {
        const QString driver = accelDriverName(device);
        const QString vendor = readTextFile(device + QStringLiteral("/device/vendor"));

        // 优先 Intel NPU 的累积忙时计数器。
        const QString busyTimeUs = device + QStringLiteral("/device/npu_busy_time_us");
        if (driver == QLatin1String("intel_vpu") || vendor == QLatin1String("0x8086")) {
            qreal value = 0.0;
            if (updateUsageFromBusyUs(busyTimeUs, &m_cumulativeSamples, &value)) {
                best = qMax(best, value);
                found = true;
                m_npuSource = NpuSource::CumulativePath;
                m_npuPath = busyTimeUs;
                continue;
            }
            // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
            if (QFileInfo::exists(busyTimeUs)) {
                m_npuSource = NpuSource::CumulativePath;
                m_npuPath = busyTimeUs;
                continue;
            }
        }

        // AMD/Rockchip 等无统一接口：按候选忙时文件依次尝试，缺失则不伪造数值。
        const QStringList candidates = {
            device + QStringLiteral("/device/npu_busy_percent"),
            busyTimeUs,
            device + QStringLiteral("/device/usage"),
            device + QStringLiteral("/device/npu_usage"),
        };
        for (const QString &path : candidates) {
            qreal value = 0.0;
            if (path == busyTimeUs) {
                if (updateUsageFromBusyUs(path, &m_cumulativeSamples, &value)) {
                    best = qMax(best, value);
                    found = true;
                    m_npuSource = NpuSource::CumulativePath;
                    m_npuPath = path;
                    break;
                }
                // 首次采样仅建立基线；路径可读时直接缓存，下一周期计算。
                if (QFileInfo::exists(path)) {
                    m_npuSource = NpuSource::CumulativePath;
                    m_npuPath = path;
                    break;
                }
            } else if (readPercentFile(path, &value)) {
                best = qMax(best, value);
                found = true;
                m_npuSource = NpuSource::PercentPath;
                m_npuPath = path;
                break;
            }
        }
        if (found)
            break;
    }

    if (found) {
        m_npuUsage = best;
        m_npuAvailable = true;
    }
    return found;
}

void SystemInfoWorker::readNpu()
{
    m_npuUsage = 0.0;
    m_npuAvailable = false;

    if (readCachedNpu())
        return;

    const qint64 now = nowUs();
    if (m_npuLastScanUs == 0 || now - m_npuLastScanUs >= kSourceRescanIntervalUs) {
        m_npuLastScanUs = now;
        scanNpu();
    }
}
