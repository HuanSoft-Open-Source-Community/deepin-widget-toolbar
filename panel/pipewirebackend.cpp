// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pipewirebackend.h"

#include <QDebug>

#include <cmath>
#include <cstring>
#include <dlfcn.h>

// 官方 SPA POD builder 为 static inline，仅需头文件即可使用；
// 头文件缺失时回退到手写 POD（结构等价，见 buildFormatPodFallback）。
#if defined(__has_include)
#  if __has_include(<spa/pod/builder.h>) && __has_include(<spa/param/audio/raw.h>)
#    define HAVE_SPA_POD_BUILDER 1
#    include <spa/pod/builder.h>
#    include <spa/param/format.h>
#    include <spa/param/audio/raw.h>
#    include <spa/utils/type.h>
#  endif
#endif
#ifndef HAVE_SPA_POD_BUILDER
#  define HAVE_SPA_POD_BUILDER 0
#endif

// spa/pod/pod-types.h 缺失时的类型字符常量（与官方一致）
#ifndef SPA_POD_TYPE_Id
#  define SPA_POD_TYPE_Id 'I'
#  define SPA_POD_TYPE_Int 'i'
#  define SPA_POD_TYPE_Array 'a'
#  define SPA_POD_TYPE_String 's'
#endif

namespace {

constexpr char kPwSoname[] = "libpipewire-0.3.so.0";

// ---- SPA / PipeWire 常量（与运行时 ABI 一致） ----
constexpr uint32_t kSpaTypeObject = 15;
constexpr uint32_t kSpaTypeId = 3;
constexpr uint32_t kSpaTypeInt = 4;
constexpr uint32_t kSpaParamFormat = 4;
constexpr uint32_t kSpaFormatMediaType = 1;
constexpr uint32_t kSpaFormatMediaSubtype = 2;
constexpr uint32_t kSpaFormatAudioFormat = 0x10001;
constexpr uint32_t kSpaFormatAudioRate = 0x10003;
constexpr uint32_t kSpaFormatAudioChannels = 0x10004;
constexpr uint32_t kSpaFormatAudioPosition = 0x10005;
constexpr uint32_t kSpaTypeArray = 13;
constexpr uint32_t kSpaMediaTypeAudio = 1;
constexpr uint32_t kSpaMediaSubtypeRaw = 1;
constexpr uint32_t kSpaAudioFormatF32 = 283;
constexpr uint32_t kSpaChannelFL = 3;
constexpr uint32_t kSpaChannelFR = 4;

constexpr int kPwDirectionInput = 0;
constexpr uint32_t kPwStreamFlagAutoconnect = 1u;
constexpr uint32_t kPwStreamFlagMapBuffers = 4u;
constexpr int kPwStreamStateStreaming = 3;

constexpr uint32_t kPwVersionStreamEvents = 2;
constexpr uint32_t kSampleRate = 48000;
constexpr uint32_t kChannels = 2;

// 格式 POD：F32 48000Hz 2ch，带声道位置 [FL FR]（2ch 无位置会协商失败）
constexpr int kPodBytes = 256;
void buildFormatPod(uint8_t *out)
{
#if HAVE_SPA_POD_BUILDER
    // 官方 inline builder 生成，保证 POD 布局正确。
    // 注意：类型参数是格式字符串（"I"=Id，"i"=Int），数组子类型是数字 pod 类型。
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(out, kPodBytes);
    const uint32_t position[2] = { kSpaChannelFL, kSpaChannelFR };
    // 协商 offer 用 EnumFormat（=3）；Format(=4) 是协商结果参数，不能作 offer
    spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType,       "I", SPA_MEDIA_TYPE_audio,
        SPA_FORMAT_mediaSubtype,    "I", SPA_MEDIA_SUBTYPE_raw,
        SPA_FORMAT_AUDIO_format,    "I", SPA_AUDIO_FORMAT_F32,
        SPA_FORMAT_AUDIO_rate,      "i", static_cast<int32_t>(kSampleRate),
        SPA_FORMAT_AUDIO_channels,  "i", static_cast<int32_t>(kChannels),
        SPA_FORMAT_AUDIO_position,  "a", static_cast<int>(sizeof(uint32_t)),
            static_cast<int>(kSpaTypeId), 2, const_cast<uint32_t *>(position),
        0);
#else
    // 无 SPA 头文件时的等价手写 POD（结构同上）
    uint32_t *p = reinterpret_cast<uint32_t *>(out);
    *p++ = 160;
    *p++ = kSpaTypeObject;
    *p++ = kSpaParamFormat;
    *p++ = 0;
    auto prop = [&p](uint32_t key, uint32_t type, uint32_t data) {
        *p++ = key;
        *p++ = 0;
        *p++ = 4;
        *p++ = type;
        *p++ = data;
        *p++ = 0;
    };
    prop(kSpaFormatMediaType, kSpaTypeId, kSpaMediaTypeAudio);
    prop(kSpaFormatMediaSubtype, kSpaTypeId, kSpaMediaSubtypeRaw);
    prop(kSpaFormatAudioFormat, kSpaTypeId, kSpaAudioFormatF32);
    prop(kSpaFormatAudioRate, kSpaTypeInt, kSampleRate);
    prop(kSpaFormatAudioChannels, kSpaTypeInt, kChannels);
    *p++ = kSpaFormatAudioPosition;
    *p++ = 0;
    *p++ = 16;
    *p++ = kSpaTypeArray;
    *p++ = 4;
    *p++ = 2;
    *p++ = kSpaChannelFL;
    *p++ = kSpaChannelFR;
#endif
}

#define LOAD_SYMBOL(api, handle, name)     do {         *(void **)(&(api).name) = dlsym(handle, "pw_" #name);         if (!(api).name) {             qWarning() << "PipeWireCaptureBackend: dlsym pw_" #name " failed:" << dlerror();             return false;         }     } while (0)

} // namespace

PipeWireCaptureBackend::PipeWireCaptureBackend()
{
}

PipeWireCaptureBackend::~PipeWireCaptureBackend()
{
    stop();
}

bool PipeWireCaptureBackend::probe()
{
    return loadPw();
}

bool PipeWireCaptureBackend::start(SampleSink sink)
{
    if (m_running.load())
        return true;
    m_sink = std::move(sink);
    m_stop.store(false);
    m_thread = std::thread([this]() { run(); });
    m_running.store(true);
    return true;
}

void PipeWireCaptureBackend::stop()
{
    if (!m_running.load())
        return;
    m_stop.store(true);
    if (m_mainLoop && m_pw.main_loop_quit)
        m_pw.main_loop_quit(m_mainLoop);
    if (m_thread.joinable())
        m_thread.join();
    m_running.store(false);
    m_sink = nullptr;
}

bool PipeWireCaptureBackend::loadPw()
{
    if (m_pw.handle)
        return true;
    void *handle = dlopen(kPwSoname, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        m_lastError = QStringLiteral("dlopen libpipewire-0.3.so.0 failed");
        return false;
    }
    m_pw.handle = handle;
    LOAD_SYMBOL(m_pw, handle, init);
    LOAD_SYMBOL(m_pw, handle, main_loop_new);
    LOAD_SYMBOL(m_pw, handle, main_loop_get_loop);
    LOAD_SYMBOL(m_pw, handle, main_loop_run);
    LOAD_SYMBOL(m_pw, handle, main_loop_quit);
    LOAD_SYMBOL(m_pw, handle, main_loop_destroy);
    LOAD_SYMBOL(m_pw, handle, context_new);
    LOAD_SYMBOL(m_pw, handle, context_connect);
    LOAD_SYMBOL(m_pw, handle, context_destroy);
    LOAD_SYMBOL(m_pw, handle, core_disconnect);
    LOAD_SYMBOL(m_pw, handle, core_get_registry);
    LOAD_SYMBOL(m_pw, handle, registry_add_listener);
    LOAD_SYMBOL(m_pw, handle, registry_destroy);
    LOAD_SYMBOL(m_pw, handle, properties_new);
    LOAD_SYMBOL(m_pw, handle, properties_free);
    LOAD_SYMBOL(m_pw, handle, stream_new);
    LOAD_SYMBOL(m_pw, handle, stream_add_listener);
    LOAD_SYMBOL(m_pw, handle, stream_connect);
    LOAD_SYMBOL(m_pw, handle, stream_get_state);
    LOAD_SYMBOL(m_pw, handle, stream_set_active);
    LOAD_SYMBOL(m_pw, handle, stream_dequeue_buffer);
    LOAD_SYMBOL(m_pw, handle, stream_queue_buffer);
    LOAD_SYMBOL(m_pw, handle, stream_disconnect);
    LOAD_SYMBOL(m_pw, handle, stream_destroy);
    return true;
}

const char *PipeWireCaptureBackend::dictLookup(const SpaDict *dict, const char *key)
{
    if (!dict || !key)
        return nullptr;
    for (uint32_t i = 0; i < dict->n_items; ++i) {
        if (dict->items[i].key && std::strcmp(dict->items[i].key, key) == 0)
            return dict->items[i].value;
    }
    return nullptr;
}

void PipeWireCaptureBackend::registryGlobalCb(void *data, uint32_t id, uint32_t,
                                              const char *type, uint32_t, const SpaDict *props)
{
    auto *self = static_cast<PipeWireCaptureBackend *>(data);
    if (!self || self->m_stream || !type)
        return;
    if (std::strcmp(type, "PipeWire:Interface:Node") != 0)
        return;
    const char *mclass = dictLookup(props, "media.class");
    if (!mclass || std::strcmp(mclass, "Audio/Sink") != 0)
        return;   // 安全红线：只考虑输出 sink，绝不触碰 Audio/Source（麦克风）
    const char *name = dictLookup(props, "node.name");
    if (!name)
        return;
    // 跳过虚拟设备：null-sink / echo-cancel 不产生“系统正在播放的声音”
    if (std::strstr(name, "null") || std::strstr(name, "echo"))
        return;

    // 第一个真实 sink 即视为默认输出（单声卡系统即为默认；
    // null/echo 已在上方跳过）。在注册表回调内创建流（同一线程）。
    self->createStream(id);
}

void PipeWireCaptureBackend::streamStateCb(void *data, int, int newState, const char *error)
{
    auto *self = static_cast<PipeWireCaptureBackend *>(data);
    if (!self)
        return;
    if (newState == kPwStreamStateStreaming) {
        self->m_active.store(true);
    } else if (newState < 0) {
        self->m_active.store(false);
        self->m_lastError = QString::fromUtf8(error ? error : "pipewire stream error");
    }
}

void PipeWireCaptureBackend::streamProcessCb(void *data)
{
    auto *self = static_cast<PipeWireCaptureBackend *>(data);
    if (!self || !self->m_stream || !self->m_sink || !self->m_pw.stream_dequeue_buffer)
        return;

    auto *buffer = static_cast<PwBuffer *>(self->m_pw.stream_dequeue_buffer(self->m_stream));
    if (!buffer)
        return;
    const auto *spaBuf = static_cast<const SpaBuffer *>(buffer->buffer);
    if (spaBuf && spaBuf->n_datas > 0) {
        const SpaData *d = &spaBuf->datas[0];
        // 防御：buffer 未映射/数据指针无效时跳过，避免越界
        if (!d->data || !d->chunk || self->m_channels <= 0)
            goto out;
        const uint32_t bytes = d->chunk->size;
        const auto *raw = static_cast<const char *>(d->data) + d->chunk->offset;
        uint32_t frames = bytes / (sizeof(float) * static_cast<uint32_t>(self->m_channels));
        if (frames > 8192)
            frames = 8192;
        if (frames > 0) {
            if (self->m_channels >= 2) {
                // 交错立体声 → 单声道
                static thread_local float mono[8192];
                const uint32_t n = frames < 8192 ? frames : 8192;
                const auto *f = reinterpret_cast<const float *>(raw);
                for (uint32_t i = 0; i < n; ++i)
                    mono[i] = (f[i * 2] + f[i * 2 + 1]) * 0.5f;
                self->m_sink(mono, n);
            } else {
                self->m_sink(reinterpret_cast<const float *>(raw), frames);
            }
        }
    }
out:
    self->m_pw.stream_queue_buffer(self->m_stream, buffer);
}

void PipeWireCaptureBackend::createStream(uint32_t sinkId)
{
    if (m_stream || !m_core)
        return;

    void *props = m_pw.properties_new("media.class", "Stream/Input/Audio",
                                      "media.category", "Capture",
                                      "media.role", "Music",
                                      "node.name", "ds-widget-toolbar-spectrum",
                                      nullptr);
    // 注意：pw_stream_new 会接管 props（内部持有引用），此处不得手动释放
    m_stream = m_pw.stream_new(m_core, "spectrum-monitor", props);
    if (!m_stream) {
        m_lastError = QStringLiteral("pw_stream_new failed");
        setActiveInternal(false);
        return;
    }

    m_channels = kChannels;
    std::memset(&m_streamHook, 0, sizeof(m_streamHook));
    static const PwStreamEvents streamEvents = {
        /* version */ kPwVersionStreamEvents,
        /* destroy */ nullptr,
        /* state_changed */ &PipeWireCaptureBackend::streamStateCb,
        /* control_info */ nullptr,
        /* io_changed */ nullptr,
        /* param_changed */ nullptr,
        /* add_buffer */ nullptr,
        /* remove_buffer */ nullptr,
        /* process */ &PipeWireCaptureBackend::streamProcessCb,
        /* drained */ nullptr,
        /* command */ nullptr,
        /* trigger_done */ nullptr
    };
    m_pw.stream_add_listener(m_stream, &m_streamHook, &streamEvents, this);

    // 格式 POD：F32 48000Hz 2ch；以 sink 节点 id 为 target 即连其 monitor 端口
    uint8_t pod[kPodBytes] = {0};
    buildFormatPod(pod);
    const void *params[1] = { reinterpret_cast<const void *>(pod) };
    const int rc = m_pw.stream_connect(m_stream, kPwDirectionInput, sinkId,
                                       kPwStreamFlagAutoconnect | kPwStreamFlagMapBuffers,
                                       params, 1);
    if (rc < 0) {
        m_lastError = QStringLiteral("pw_stream_connect failed") + QString::number(rc);
        m_pw.stream_destroy(m_stream);
        m_stream = nullptr;
        setActiveInternal(false);
        return;
    }
    // 捕获流默认停在 PAUSED，需显式激活才进入 STREAMING
    if (m_pw.stream_set_active)
        m_pw.stream_set_active(m_stream, true);
}

void PipeWireCaptureBackend::setActiveInternal(bool active)
{
    m_active.store(active);
}

void PipeWireCaptureBackend::run()
{
    if (!loadPw()) {
        setActiveInternal(false);
        return;
    }

    m_pw.init(nullptr, nullptr);
    m_mainLoop = m_pw.main_loop_new(nullptr);
    if (!m_mainLoop) {
        m_lastError = QStringLiteral("pw_main_loop_new failed");
        setActiveInternal(false);
        return;
    }
    m_context = m_pw.context_new(m_pw.main_loop_get_loop(m_mainLoop), nullptr, 0);
    if (!m_context) {
        m_lastError = QStringLiteral("pw_context_new failed");
        setActiveInternal(false);
        return;
    }
    m_core = m_pw.context_connect(m_context, nullptr, 0);
    if (!m_core) {
        m_lastError = QStringLiteral("pw_context_connect failed");
        setActiveInternal(false);
        return;
    }
    m_registry = m_pw.core_get_registry(m_core, 0, 0);
    if (!m_registry) {
        m_lastError = QStringLiteral("pw_core_get_registry failed");
        setActiveInternal(false);
        return;
    }

    static const PwRegistryEvents registryEvents = {
        /* version */ 0,
        /* global */ &PipeWireCaptureBackend::registryGlobalCb,
        /* global_remove */ nullptr
    };
    std::memset(&m_registryHook, 0, sizeof(m_registryHook));
    m_pw.registry_add_listener(m_registry, &m_registryHook, &registryEvents, this);

    // 运行事件循环：注册表枚举回调在循环内触发，找到 sink 后创建流
    m_pw.main_loop_run(m_mainLoop);

    // 循环结束（stop 或错误）：收尾
    if (m_stream) {
        m_pw.stream_disconnect(m_stream);
        m_pw.stream_destroy(m_stream);
        m_stream = nullptr;
    }
    if (m_registry) {
        m_pw.registry_destroy(m_registry);
        m_registry = nullptr;
    }
    if (m_core) {
        m_pw.core_disconnect(m_core);
        m_core = nullptr;
    }
    if (m_context) {
        m_pw.context_destroy(m_context);
        m_context = nullptr;
    }
    if (m_mainLoop) {
        m_pw.main_loop_destroy(m_mainLoop);
        m_mainLoop = nullptr;
    }
    if (m_pw.handle) {
        dlclose(m_pw.handle);
        m_pw.handle = nullptr;
    }
    setActiveInternal(false);
}
