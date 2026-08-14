# 系统监视指标设计

本文档说明 `deepin-widget-toolbar` 资源监视小组件的指标口径、数据源、计算公式与降级策略，供后续维护与审计参考。

## 指标一览

| 指标 | 口径 | 主要数据源 |
|------|------|-----------|
| CPU | 全 CPU 非空闲时间占比 | `/proc/stat` |
| MEM | 已使用内存占比 | `/proc/meminfo`（`MemTotal` / `MemAvailable`） |
| DISK | iostat 风格 IO 忙时占比（`%util`） | `/proc/diskstats` |
| GPU | 当前 GPU 占用 0~1 | NVIDIA NVML；AMD/Intel DRM sysfs |
| NPU | 当前 NPU 占用 0~1 | `/sys/class/accel` 暴露的忙时/占用指标 |

## 计算公式

### CPU

读取 `/proc/stat` 第一行 `cpu` 的累积时间片，对相邻两次采样做差分：

```text
cpuUsage = 1 - Δ(idle + iowait) / Δ(total)
```

### 内存

```text
memUsedPercent = 1 - MemAvailable / MemTotal
```

数值解析前对 `/proc/meminfo` 行执行空白归一化，避免连续空格导致旧实现取到空字段、内存占用始终为 0%。

### 磁盘 IO 忙时占比

读取 `/proc/diskstats` 的 `ms_doing_io` 字段（按空格切分后的第 13 列、0 起始下标 12），聚合非 loop、非分区物理块设备：

```text
diskBusyPercent = ΔΣ(ms_doing_io) / HZ / ΔelapsedSeconds
```

- `HZ` 使用 `sysconf(_SC_CLK_TCK)` 获取，失败时回退 100。
- 仅统计 `nvme*`、`sd*`、`mmcblk*`、`vd*`、`xvd*` 设备；通过 `/sys/class/block/<name>/partition` 排除分区，并排除 `dm`、`md`、`loop`、`ram`、`zram`，避免映射设备重复计数。
- 结果钳制到 0~1。

### GPU

- **NVIDIA**：通过 `QLibrary` 在运行时动态加载 `nvidia-ml.so.1`（回退 `nvidia-ml`），调用 `nvmlInit_v2`、`nvmlDeviceGetCount_v2`、`nvmlDeviceGetHandleByIndex_v2` 和 `nvmlDeviceGetUtilizationRates`。多卡时取最忙设备；加载或调用失败时标记为不可用，不引入编译期 NVML 依赖。
- **AMD**：优先读取 `/sys/class/drm/card*/device/gpu_busy_percent`，缺失时回退关联 hwmon 目录下的 `busy`。
- **Intel i915**：读取 `gt/gt0/gt_busy_percent`（必要时尝试 `media_busy_percent`）。
- **Intel Xe**：内核可能不提供标准百分比文件，此时读取 `tile0/gt0/gtidle/idle_residency_ms` 累积值，按两次采样的空闲时长估算：

```text
gpuBusy = 1 - ΔidleResidencyMs / ΔelapsedMs
```

其他 GPU 依次尝试常见 busy 文件；无法读取时不伪造数据，面板显示 N/A。

### NPU

扫描 `/sys/class/accel/accel*`，按驱动名和 PCI vendor 识别设备：

- **Intel（`intel_vpu`）**：读取 `device/npu_busy_time_us` 累积忙时计数器：

```text
npuUsage = ΔbusyTimeUs / ΔelapsedUs
```

- **AMD（`amdxdna`）与其他 NPU**：依次尝试 `npu_busy_percent`、`npu_busy_time_us`、`usage`、`npu_usage`。只有内核暴露可读忙时指标时才显示占用；否则显示 N/A。
- 多设备时取最忙设备。

## 思路来源

GPU/NPU 的设备发现、sysfs 路径和 NVML 使用方式的实现思路参考 [GNOME Resources](https://github.com/nokyan/resources)。该仓库已归档，并迁移至 [GNOME Incubator Resources](https://gitlab.gnome.org/Incubator/Resources)。本项目按 Qt/C++ 重新实现并只保留本面板需要的指标，未复制其代码。

磁盘 IO 忙时占比采用 Linux `iostat`/`/proc/diskstats` 的通用 `%util` 口径。
