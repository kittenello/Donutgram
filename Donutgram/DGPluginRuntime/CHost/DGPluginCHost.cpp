#include "DGPluginCHost.h"
#include "quickjs.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <map>
#include <set>
#include <cmath>
#include <string>
#include <vector>
#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <pthread.h>
#else
#include <time.h>
#endif

struct DGJSHost {
    JSRuntime *runtime = nullptr;
    JSContext *context = nullptr;
    JSValue task = JS_UNDEFINED;
    std::atomic<bool> stopped{false};
    std::chrono::steady_clock::time_point deadline;
    DGJSRequest request;
    void *opaque;
    std::map<std::string, std::string> files;
    size_t total = 0;
    const char *error = nullptr;
    bool modulePhase = false;
    // The module and activate() are evaluating: a rejection there means the plugin cannot run.
    bool activating = false;
    // The current dispatch's promise was rejected; `rejection` holds the sanitized error code.
    bool rejected = false;
    std::string rejection;
    bool active = false;
    bool busy = false;
    unsigned jobs = 0;
    std::chrono::steady_clock::time_point cpuWindowStart = std::chrono::steady_clock::now();
    uint64_t cpuWindowUsed = 0;
    // Thread CPU time the current operation has used, and its budget (1 s activation, 250 ms callbacks).
    uint64_t opCpuUsed = 0;
    uint64_t opCpuBudget = 0;
    uint64_t cpuSliceStart = 0;
    unsigned cpuSliceDepth = 0;
    bool cpuClockAvailable = false;
    std::set<int64_t> pendingNative;
    bool waitingNative = false;
    std::chrono::steady_clock::duration activeRemaining{};
    std::chrono::steady_clock::duration nativeWaitUsed{};
    std::chrono::steady_clock::time_point nativeWaitStart;
    std::chrono::steady_clock::time_point nativeWaitUntil;
};

static void fail(DGJSHost *h, const char *message);

static bool threadCPU(uint64_t &result) {
#if defined(_WIN32)
    FILETIME created, exited, kernel, user;
    if (!GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)) return false;
    ULARGE_INTEGER k, u;
    k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
    u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
    result = (k.QuadPart + u.QuadPart) * 100;
#elif defined(__APPLE__)
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(pthread_mach_thread_np(pthread_self()), THREAD_BASIC_INFO, reinterpret_cast<thread_info_t>(&info), &count) != KERN_SUCCESS) return false;
    result = uint64_t(info.user_time.seconds + info.system_time.seconds) * 1000000000 + uint64_t(info.user_time.microseconds + info.system_time.microseconds) * 1000;
#else
    struct timespec value;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) != 0) return false;
    result = uint64_t(value.tv_sec) * 1000000000 + uint64_t(value.tv_nsec);
#endif
    return true;
}

struct ExecutionSlice {
    DGJSHost *host;
    explicit ExecutionSlice(DGJSHost *h) : host(h) {
        if (h->cpuSliceDepth++ == 0) {
            auto now = std::chrono::steady_clock::now();
            if (now - h->cpuWindowStart >= std::chrono::seconds(60)) { h->cpuWindowStart = now; h->cpuWindowUsed = 0; }
            h->cpuClockAvailable = threadCPU(h->cpuSliceStart);
            if (!h->cpuClockAvailable) fail(h, "cpu_clock_unavailable");
        }
    }
    ~ExecutionSlice() {
        if (--host->cpuSliceDepth == 0 && host->cpuClockAvailable) {
            uint64_t now;
            if (threadCPU(now) && now >= host->cpuSliceStart) {
                host->cpuWindowUsed += now - host->cpuSliceStart;
                host->opCpuUsed += now - host->cpuSliceStart;
            }
        }
    }
};

static void fail(DGJSHost *h, const char *message) {
    if (!h->error) h->error = message;
    h->stopped.store(true);
    JS_SetStopped(h->runtime);
}

// An operation's budget is thread CPU time, so a plugin is not stopped because the device was busy elsewhere and
// its thread waited for a core. The wall-clock deadline stays as a far looser backstop (eight times the budget,
// at least two seconds); native waits count against neither.
static void beginOperation(DGJSHost *h, std::chrono::milliseconds budget) {
    h->opCpuUsed = 0;
    h->opCpuBudget = uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(budget).count());
    h->deadline = std::chrono::steady_clock::now() + std::max(budget * 8, std::chrono::milliseconds(2000));
    h->nativeWaitUsed = std::chrono::steady_clock::duration::zero();
    h->waitingNative = false;
    h->busy = true;
    h->jobs = 0;
    JS_SetNativeWorkLimit(h->runtime, 8000000);
}

static bool resumeNative(DGJSHost *h) {
    if (!h->waitingNative) return true;
    auto now = std::chrono::steady_clock::now();
    if (now >= h->nativeWaitUntil) { fail(h, "native_wait_timeout"); return false; }
    h->nativeWaitUsed += now - h->nativeWaitStart;
    h->deadline = now + h->activeRemaining;
    h->waitingNative = false;
    return true;
}

static int interrupt(JSRuntime *, void *opaque) {
    auto *h = static_cast<DGJSHost *>(opaque);
    if (h->stopped.load()) { if (!h->error) h->error = "cancelled"; JS_SetStopped(h->runtime); return 1; }
    if (JS_IsStopped(h->runtime)) { fail(h, "native_work_limit"); return 1; }
    uint64_t cpuNow;
    if (h->cpuClockAvailable && threadCPU(cpuNow) && cpuNow >= h->cpuSliceStart) {
        uint64_t slice = cpuNow - h->cpuSliceStart;
        if (h->cpuWindowUsed + slice >= 2000000000) { fail(h, "cpu_budget_exceeded"); return 1; }
        if (h->opCpuBudget && h->opCpuUsed + slice >= h->opCpuBudget) { fail(h, "execution_timeout"); return 1; }
    }
    if (std::chrono::steady_clock::now() >= h->deadline) {
        fail(h, "execution_timeout");
        return 1;
    }
    return 0;
}

static void memoryLimit(JSRuntime *, void *opaque) {
    fail(static_cast<DGJSHost *>(opaque), "memory_limit");
}

static bool validPath(const std::string &path) {
    if (path.empty() || path.size() > 240 || path.front() == '/' || path.find('\\') != std::string::npos || path.find(':') != std::string::npos || path.find('\0') != std::string::npos) return false;
    size_t start = 0;
    while (start < path.size()) {
        size_t end = path.find('/', start);
        std::string part = path.substr(start, end == std::string::npos ? end : end-start);
        if (part.empty() || part == "." || part == "..") return false;
        if (end == std::string::npos) return true;
        start = end+1;
    }
    return false;
}

static char *normalize(JSContext *ctx, const char *base, const char *name, void *opaque) {
    auto *h = static_cast<DGJSHost *>(opaque);
    std::string path(name);
    if (path.rfind("./", 0) == 0) {
        std::string parent(base);
        auto slash = parent.rfind('/');
        path = (slash == std::string::npos ? "" : parent.substr(0, slash+1)) + path.substr(2);
    }
    if (!validPath(path) || path.size() < 3 || path.substr(path.size()-3) != ".js" || !h->files.count(path)) {
        JS_ThrowTypeError(ctx, "module_not_found");
        return nullptr;
    }
    return js_strdup(ctx, path.c_str());
}

static JSModuleDef *loadModule(JSContext *ctx, const char *name, void *opaque) {
    auto *h = static_cast<DGJSHost *>(opaque);
    auto it = h->files.find(name);
    if (it == h->files.end()) { JS_ThrowTypeError(ctx, "module_not_found"); return nullptr; }
    JSValue compiled = JS_Eval(ctx, it->second.c_str(), it->second.size(), name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(compiled)) return nullptr;
    auto *module = static_cast<JSModuleDef *>(JS_VALUE_GET_PTR(compiled));
    JS_FreeValue(ctx, compiled);
    return module;
}

static JSValue requestNative(JSContext *ctx, JSValueConst, int argc, JSValueConst *argv) {
    auto *h = static_cast<DGJSHost *>(JS_GetContextOpaque(ctx));
    if (interrupt(h->runtime, h)) return JS_EXCEPTION;
    if (argc != 1 || !JS_IsString(argv[0])) return JS_ThrowTypeError(ctx, "invalid_request");
    size_t count = 0;
    const char *json = JS_ToCStringLen(ctx, &count, argv[0]);
    if (!json) return JS_EXCEPTION;
    if (count > 65536) { JS_FreeCString(ctx, json); return JS_ThrowRangeError(ctx, "request_limit"); }
    JSValue envelope = JS_ParseJSON(ctx, json, count, "<request>");
    if (JS_IsException(envelope)) { JS_FreeCString(ctx, json); return JS_EXCEPTION; }
    JSValue idValue = JS_GetPropertyStr(ctx, envelope, "id");
    double number = 0;
    bool valid = JS_IsNumber(idValue) && JS_ToFloat64(ctx, &number, idValue) == 0 && std::isfinite(number) && number >= 1 && number <= 9007199254740991.0 && std::floor(number) == number;
    JS_FreeValue(ctx, idValue); JS_FreeValue(ctx, envelope);
    if (!valid || h->pendingNative.size() >= 64 || !h->pendingNative.insert(static_cast<int64_t>(number)).second) {
        JS_FreeCString(ctx, json);
        return JS_ThrowRangeError(ctx, "request_limit");
    }
    h->request(h->opaque, json);
    JS_FreeCString(ctx, json);
    return JS_UNDEFINED;
}

static bool validRejectionCode(const std::string &code) {
    if (code.empty() || code.size() > 64) return false;
    for (char c : code) {
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-')) return false;
    }
    return true;
}

// Records why the current dispatch's promise was rejected without running any plugin code: the `code` of an
// Error is read only when it is an own data property (a getter or a Proxy is never invoked).
static void recordRejection(DGJSHost *h) {
    h->rejected = true;
    h->rejection = "plugin_error";
    JSValue reason = JS_PromiseResult(h->context, h->task);
    if (JS_IsError(reason)) {
        JSAtom atom = JS_NewAtom(h->context, "code");
        JSPropertyDescriptor descriptor;
        int found = atom == JS_ATOM_NULL ? -1 : JS_GetOwnProperty(h->context, &descriptor, reason, atom);
        if (atom != JS_ATOM_NULL) JS_FreeAtom(h->context, atom);
        if (found > 0) {
            if (!(descriptor.flags & JS_PROP_GETSET) && JS_IsString(descriptor.value)) {
                size_t length = 0;
                const char *text = JS_ToCStringLen(h->context, &length, descriptor.value);
                if (text) {
                    std::string code(text, length);
                    JS_FreeCString(h->context, text);
                    if (validRejectionCode(code)) h->rejection = code;
                }
            }
            JS_FreeValue(h->context, descriptor.value);
            JS_FreeValue(h->context, descriptor.getter);
            JS_FreeValue(h->context, descriptor.setter);
        }
        if (found < 0 || JS_HasException(h->context)) JS_FreeValue(h->context, JS_GetException(h->context));
    }
    JS_FreeValue(h->context, reason);
}

static int capture(DGJSHost *h) {
    JSValue exception = JS_GetException(h->context);
    JS_FreeValue(h->context, exception);
    fail(h, JS_IsStopped(h->runtime) ? "native_work_limit" : "javascript_error");
    return -1;
}

static JSValue call(DGJSHost *h, const char *name, int count, JSValue *args) {
    JSValue global = JS_GetGlobalObject(h->context);
    JSValue fn = JS_GetPropertyStr(h->context, global, name);
    JSValue result = JS_Call(h->context, fn, JS_UNDEFINED, count, args);
    JS_FreeValue(h->context, fn);
    JS_FreeValue(h->context, global);
    return result;
}

extern "C" DGJSHost *dgjs_create(DGJSRequest request, void *opaque) {
    if (!request) return nullptr;
    auto *h = new DGJSHost;
    h->request = request; h->opaque = opaque;
    h->deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
    h->runtime = JS_NewRuntime();
    if (!h->runtime) { delete h; return nullptr; }
    JS_SetMemoryLimit(h->runtime, 16 * 1024 * 1024);
    // The limit only protects the process when the calling thread's real stack is several times larger: the
    // Swift wrapper runs every call on its own 4 MiB thread (DGPluginRuntimeThread), never on a 512 KiB
    // dispatch worker, where a deep recursion would reach the guard page before this check.
    JS_SetMaxStackSize(h->runtime, 512 * 1024);
    JS_SetMemoryLimitFunc(h->runtime, memoryLimit, h);
    JS_SetInterruptHandler(h->runtime, interrupt, h);
    JS_SetModuleLoaderFunc(h->runtime, normalize, loadModule, h);
    h->context = JS_NewContext(h->runtime);
    if (!h->context) { JS_FreeRuntime(h->runtime); delete h; return nullptr; }
    JS_SetContextOpaque(h->context, h);
    JS_SetDynamicCompilationAllowed(h->context, false);
    JSValue global = JS_GetGlobalObject(h->context);
    JS_SetPropertyStr(h->context, global, "__dgNative", JS_NewCFunction(h->context, requestNative, "native", 1));
    JS_FreeValue(h->context, global);
    return h;
}

extern "C" int dgjs_add_file(DGJSHost *h, const char *path, const uint8_t *bytes, size_t size) {
    if (h->active || h->files.size() >= 128 || !validPath(path) || size > 1024 * 1024 || size > 4 * 1024 * 1024 - h->total || h->files.count(path)) return -1;
    if (size && !bytes) return -1;
    h->files.emplace(path, std::string(size ? reinterpret_cast<const char *>(bytes) : "", size));
    h->total += size;
    return 0;
}

extern "C" int dgjs_start(DGJSHost *h, const char *entry, const char *bootstrap, const char *environment) {
    if (h->active || h->stopped.load() || !h->files.count(entry) || strlen(environment) > 65536) return -1;
    h->active = true;
    h->activating = true;
    h->rejected = false;
    h->rejection.clear();
    ExecutionSlice slice(h);
    beginOperation(h, std::chrono::milliseconds(1000));
    JS_UpdateStackTop(h->runtime);
    JSValue result = JS_Eval(h->context, bootstrap, strlen(bootstrap), "<bootstrap>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result)) return capture(h);
    JS_FreeValue(h->context, result);
    JSValue env = JS_ParseJSON(h->context, environment, strlen(environment), "<environment>");
    if (JS_IsException(env)) return capture(h);
    JSValue arg[1] = {env};
    result = call(h, "__dgConfigure", 1, arg);
    JS_FreeValue(h->context, env);
    if (JS_IsException(result)) return capture(h);
    JS_FreeValue(h->context, result);
    auto &source = h->files.at(entry);
    h->task = JS_Eval(h->context, source.c_str(), source.size(), entry, JS_EVAL_TYPE_MODULE);
    h->modulePhase = true;
    return dgjs_pump(h);
}

extern "C" int dgjs_pump(DGJSHost *h) {
    ExecutionSlice slice(h);
    JS_UpdateStackTop(h->runtime);
    if (h->waitingNative) {
        if (h->stopped.load() || JS_IsStopped(h->runtime)) return -1;
        if (std::chrono::steady_clock::now() >= h->nativeWaitUntil) { fail(h, "native_wait_timeout"); return -1; }
        return 2;
    }
    if (interrupt(h->runtime, h)) return -1;
    for (unsigned slice = 0; slice < 256; ++slice) {
        if (++h->jobs > 4096) { fail(h, "microtask_limit"); return -1; }
        if (JS_IsException(h->task)) return capture(h);
        auto state = JS_PromiseState(h->context, h->task);
        if (state == JS_PROMISE_REJECTED) {
            // A rejected module or activate() leaves nothing to run. A rejected command, event, callback or
            // transform is the plugin's own error: the runtime stays usable and the operation ends, once its
            // detached work drains, with the error code in dgjs_rejection().
            if (h->modulePhase || h->activating) { fail(h, "promise_rejected"); return -1; }
            if (!h->rejected) recordRejection(h);
        }
        if (state != JS_PROMISE_PENDING) {
            if (h->modulePhase) {
                JS_FreeValue(h->context, h->task);
                h->task = call(h, "__dgActivate", 0, nullptr);
                h->modulePhase = false;
                continue;
            }
            if (!JS_IsJobPending(h->runtime) && h->pendingNative.empty()) { h->busy = false; h->activating = false; return 0; }
        }
        JSContext *jobContext = nullptr;
        int status = JS_ExecutePendingJob(h->runtime, &jobContext);
        if (status < 0) return capture(h);
        if (!status) {
            if (!h->pendingNative.empty()) {
                auto now = std::chrono::steady_clock::now();
                if (now >= h->deadline) { fail(h, "execution_timeout"); return -1; }
                h->activeRemaining = h->deadline - now;
                h->nativeWaitStart = now;
                h->nativeWaitUntil = now + (std::chrono::seconds(60) - h->nativeWaitUsed);
                h->waitingNative = true;
                return 2;
            }
            // Nothing can settle the operation any more: no job is queued, no native reply is outstanding, and plugins
            // have no timers. Waiting for a deadline would only hold the runtime.
            fail(h, "unresolved_promise");
            return -1;
        }
        if (interrupt(h->runtime, h)) return -1;
    }
    return 1;
}

extern "C" int dgjs_dispatch(DGJSHost *h, const char *kind, const char *payload) {
    if (!h->active || h->stopped.load() || h->busy || strlen(payload) > 65536) return -1;
    h->rejected = false;
    h->rejection.clear();
    ExecutionSlice slice(h);
    beginOperation(h, std::chrono::milliseconds(250));
    JS_UpdateStackTop(h->runtime);
    JSValue args[2] = { JS_NewString(h->context, kind), JS_ParseJSON(h->context, payload, strlen(payload), "<event>") };
    if (JS_IsException(args[1])) { JS_FreeValue(h->context, args[0]); return capture(h); }
    JS_FreeValue(h->context, h->task);
    h->task = call(h, "__dgDispatch", 2, args);
    JS_FreeValue(h->context, args[0]); JS_FreeValue(h->context, args[1]);
    return dgjs_pump(h);
}

extern "C" int dgjs_reply(DGJSHost *h, int64_t id, const char *json) {
    if (h->stopped.load() || strlen(json) > 65536) return -1;
    if (h->pendingNative.erase(id) == 0) return 0;
    ExecutionSlice slice(h);
    if (!resumeNative(h)) return -1;
    if (!h->busy) {
        beginOperation(h, std::chrono::milliseconds(250));
    }
    JS_UpdateStackTop(h->runtime);
    if (interrupt(h->runtime, h)) return -1;
    JSValue args[2] = { JS_NewInt64(h->context, id), JS_ParseJSON(h->context, json, strlen(json), "<reply>") };
    if (JS_IsException(args[1])) { JS_FreeValue(h->context, args[0]); return capture(h); }
    JSValue result = call(h, "__dgReply", 2, args);
    JS_FreeValue(h->context, args[0]); JS_FreeValue(h->context, args[1]);
    if (JS_IsException(result)) return capture(h);
    JS_FreeValue(h->context, result);
    return 0;
}

extern "C" void dgjs_stop(DGJSHost *h) { h->stopped.store(true); }
extern "C" void dgjs_destroy(DGJSHost *h) {
    if (!h) return;
    JS_FreeValue(h->context, h->task);
    JS_FreeContext(h->context); JS_FreeRuntime(h->runtime); delete h;
}
extern "C" const char *dgjs_error(DGJSHost *h) { return h->error ? h->error : "runtime_unavailable"; }
extern "C" const char *dgjs_rejection(DGJSHost *h) { return h->rejected && !h->busy ? h->rejection.c_str() : nullptr; }
