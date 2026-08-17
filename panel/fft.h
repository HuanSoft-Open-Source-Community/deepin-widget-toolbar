// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// C 风格基数-2 FFT 模块（无 Qt 依赖、无堆分配、纯 double 运算）。
//
// 用途：替代频谱分析里每帧 64bin×128 点的朴素 DFT（每分析 ~16k 次
// cos/sin 调用），把热点算术降到 448 次复数蝶形且零三角函数调用。
//
// 实现：迭代式 Cooley-Tukey（位反转置换 + 原位蝶形），twiddle 因子
// W_N^k = exp(-2πi·k/N) 按点数只计算一次并缓存。要求 N 为 2 的幂且
// ≤ 4096；本插件固定使用 N=128。
//
// 数值语义与朴素 DFT 完全一致（无 1/N 归一化），输出可直接替换旧实现。

#include <cmath>
#include <cstddef>

namespace wsf {

namespace detail {

inline void bitReverse(double *re, double *im, int n)
{
    for (int i = 1, j = 0; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            double tr = re[i]; re[i] = re[j]; re[j] = tr;
            double ti = im[i]; im[i] = im[j]; im[j] = ti;
        }
    }
}

inline void fftCore(double *re, double *im, int n,
                    const double *wr, const double *wi)
{
    for (int len = 2; len <= n; len <<= 1) {
        const int half = len >> 1;
        const int step = n / len;
        for (int base = 0; base < n; base += len) {
            for (int j = 0; j < half; ++j) {
                const double c = wr[j * step];
                const double s = wi[j * step];
                const int a = base + j;
                const int b = a + half;
                const double tr = re[b] * c - im[b] * s;
                const double ti = re[b] * s + im[b] * c;
                re[b] = re[a] - tr;
                im[b] = im[a] - ti;
                re[a] += tr;
                im[a] += ti;
            }
        }
    }
}

} // namespace detail

// 按点数缓存 twiddle 表（N/2 个复数 W_N^k）。表项为 plain double。
struct TwiddleTable {
    int n = 0;
    double wr[2048];
    double wi[2048];
};

inline const TwiddleTable &twiddleTable(int n)
{
    // 2^0..2^12 共 13 个槽位；非 2 的幂或超上限返回空表（调用方校验 t.n）
    static TwiddleTable cache[13];
    int slot = 0;
    for (int v = n; v > 1; v >>= 1)
        ++slot;
    if (slot < 0 || slot > 12 || n != (1 << slot))
        return cache[0];
    TwiddleTable &t = cache[slot];
    if (t.n != n) {
        t.n = n;
        const int half = n >> 1;
        const double k2Pi = 6.2831853071795864769252867665590057683943387987502;
        for (int k = 0; k < half; ++k) {
            const double angle = k2Pi * static_cast<double>(k) / static_cast<double>(n);
            t.wr[k] = std::cos(angle);
            t.wi[k] = -std::sin(angle);
        }
    }
    return t;
}

// 原位复数基数-2 FFT（正变换，无 1/N 归一化，与朴素 DFT 定义一致）。
// 非法 N（非 2 的幂 / > 4096）直接返回，输入保持不变。
inline void fftInPlace(double *re, double *im, int n)
{
    const TwiddleTable &t = twiddleTable(n);
    if (t.n != n)
        return;
    detail::bitReverse(re, im, n);
    detail::fftCore(re, im, n, t.wr, t.wi);
}

// 实数序列频谱幅度：in 为 n 个实数样本（可先加窗），out[0..binCount-1]
// 依次为 bin 1..binCount 的幅度（bin 0=DC 不输出）。binCount 自动钳制到
// n/2-1。返回值为未归一化幅度，与朴素 DFT 逐 bin 等价。
inline void realMagnitudes(const double *in, int n, double *out, int binCount)
{
    if (n < 2 || n > 4096)
        return;
    double re[4096];
    double im[4096];
    for (int i = 0; i < n; ++i) {
        re[i] = in[i];
        im[i] = 0.0;
    }
    fftInPlace(re, im, n);
    const int maxBin = (n >> 1) - 1;
    if (binCount > maxBin)
        binCount = maxBin;
    for (int bin = 1; bin <= binCount; ++bin)
        out[bin - 1] = std::sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
}

} // namespace wsf
