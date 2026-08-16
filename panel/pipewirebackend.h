// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "audiobackend.h"

#include <QString>

#include <atomic>
#include <cstdint>
#include <thread>

// PipeWire 原生采集后端（pipewire 未提供 pipewire-pulse 时的回退）：
// 以 dlopen 方式加载 libpipewire-0.3.so.0，枚举注册表找到真实 Audio/Sink
// 节点（默认 sink 启发式：优先 priority.session 最高的真实设备，跳过
// null-sink / echo），创建 INPUT 流并以 sink 节点 id 为目标 —— PipeWire
// 会把 input 流路由到该 sink 的 monitor 端口（“系统正在播放的声音”）。
// 安全红线：绝不连接任何 Audio/Source（麦克风）节点。
class PipeWireCaptureBackend : public CaptureBackend
{
public:
    PipeWireCaptureBackend();
    ~PipeWireCaptureBackend() override;

    const char *name() const override { return "PipeWire"; }
    bool probe() override;
    bool start(SampleSink sink) override;
    void stop() override;
    bool active() const override { return m_active.load(); }
    QString lastError() const override { return m_lastError; }

private:
    // ---- libpipewire / SPA 最小 ABI 声明 ----
    struct SpaDictItem {
        const char *key;
        const char *value;
    };
    struct SpaDict {
        uint32_t flags;
        uint32_t n_items;
        const SpaDictItem *items;
    };
    // 与 spa/utils/hook.h 一致：spa_hook = link(16) + callbacks(16) + removed + priv
    struct SpaHook {
        void *link_next;
        void *link_prev;
        const void *funcs;
        void *data;
        void (*removed)(void *hook);
        void *priv;
    };
    struct PwRegistryEvents {
        uint32_t version;
        void (*global)(void *data, uint32_t id, uint32_t permissions,
                       const char *type, uint32_t version, const SpaDict *props);
        void (*global_remove)(void *data, uint32_t id);
    };
    struct PwStreamEvents {
        uint32_t version;
        void (*destroy)(void *data);
        void (*state_changed)(void *data, int old_state, int new_state, const char *error);
        void (*control_info)(void *data, uint32_t id, void *control);
        void (*io_changed)(void *data, uint32_t id, void *area, uint32_t size);
        void (*param_changed)(void *data, uint32_t id, const void *param);
        void (*add_buffer)(void *data, void *buffer);
        void (*remove_buffer)(void *data, void *buffer);
        void (*process)(void *data);
        void (*drained)(void *data);
        void (*command)(void *data, const void *command);
        void (*trigger_done)(void *data);
    };
    struct SpaChunk {
        uint32_t offset;
        uint32_t size;
        int32_t stride;
    };
    struct SpaData {
        uint32_t type;
        uint32_t flags;
        int64_t fd;
        uint32_t mapoffset;
        uint32_t maxsize;
        void *data;
        SpaChunk *chunk;
    };
    struct SpaBuffer {
        uint32_t n_metas;
        uint32_t n_datas;
        void *metas;
        SpaData *datas;
    };
    struct PwBuffer {
        void *buffer;
        void *user_data;
        uint64_t size;
        uint64_t requested;
        uint64_t time;
    };

    struct PwApi {
        void *handle = nullptr;
        void (*init)(int *, char ***) = nullptr;
        void *(*main_loop_new)(const void *) = nullptr;
        void *(*main_loop_get_loop)(void *) = nullptr;
        void (*main_loop_run)(void *) = nullptr;
        void (*main_loop_quit)(void *) = nullptr;
        void (*main_loop_destroy)(void *) = nullptr;
        void *(*context_new)(void *, const void *, size_t) = nullptr;
        void *(*context_connect)(void *, const void *, size_t) = nullptr;
        void (*context_destroy)(void *) = nullptr;
        void (*core_disconnect)(void *) = nullptr;
        void *(*core_get_registry)(void *, uint32_t, size_t) = nullptr;
        int (*registry_add_listener)(void *, SpaHook *, const PwRegistryEvents *, void *) = nullptr;
        void (*registry_destroy)(void *) = nullptr;
        void *(*properties_new)(const char *, ...) = nullptr;
        void (*properties_free)(void *) = nullptr;
        void *(*stream_new)(void *, const char *, void *) = nullptr;
        int (*stream_add_listener)(void *, SpaHook *, const PwStreamEvents *, void *) = nullptr;
        int (*stream_connect)(void *, int, uint32_t, uint32_t, const void **, uint32_t) = nullptr;
        int (*stream_get_state)(void *) = nullptr;
        int (*stream_set_active)(void *, bool) = nullptr;
        void *(*stream_dequeue_buffer)(void *) = nullptr;
        int (*stream_queue_buffer)(void *, void *) = nullptr;
        int (*stream_disconnect)(void *) = nullptr;
        int (*stream_destroy)(void *) = nullptr;
    };

    void run();
    bool loadPw();
    void createStream(uint32_t sinkId);
    void setActiveInternal(bool active);
    static const char *dictLookup(const SpaDict *dict, const char *key);

    static void registryGlobalCb(void *data, uint32_t id, uint32_t permissions,
                                 const char *type, uint32_t version, const SpaDict *props);
    static void streamStateCb(void *data, int old_state, int new_state, const char *error);
    static void streamProcessCb(void *data);

    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_active{false};
    SampleSink m_sink;

    PwApi m_pw;
    void *m_mainLoop = nullptr;
    void *m_context = nullptr;
    void *m_core = nullptr;
    void *m_registry = nullptr;
    void *m_stream = nullptr;
    SpaHook m_registryHook{};
    SpaHook m_streamHook{};
    int m_channels = 0;
    QString m_lastError;
};
