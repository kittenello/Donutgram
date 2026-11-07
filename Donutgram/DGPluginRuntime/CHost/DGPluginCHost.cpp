#include "DGPluginCHost.h"
#include "quickjs.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <map>
#include <string>
#include <vector>

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
    bool active = false;
    bool busy = false;
    unsigned jobs = 0;
};

static void fail(DGJSHost *h, const char *message) {
    if (!h->error) h->error = message;
    h->stopped.store(true);
    JS_SetStopped(h->runtime);
}

static int interrupt(JSRuntime *, void *opaque) {
    auto *h = static_cast<DGJSHost *>(opaque);
    if (h->stopped.load()) { JS_SetStopped(h->runtime); return 1; }
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
    h->request(h->opaque, json);
    JS_FreeCString(ctx, json);
    return JS_UNDEFINED;
}

static int capture(DGJSHost *h) {
    JSValue exception = JS_GetException(h->context);
    JS_FreeValue(h->context, exception);
    fail(h, "javascript_error");
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
    h->files.emplace(path, std::string(reinterpret_cast<const char *>(bytes), size));
    h->total += size;
    return 0;
}

extern "C" int dgjs_start(DGJSHost *h, const char *entry, const char *bootstrap, const char *environment) {
    if (h->active || h->stopped.load() || !h->files.count(entry) || strlen(environment) > 65536) return -1;
    h->active = true; h->busy = true; h->jobs = 0;
    h->deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
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
    JS_UpdateStackTop(h->runtime);
    if (interrupt(h->runtime, h)) return -1;
    for (unsigned slice = 0; slice < 256; ++slice) {
        if (++h->jobs > 4096) { fail(h, "microtask_limit"); return -1; }
        if (JS_IsException(h->task)) return capture(h);
        auto state = JS_PromiseState(h->context, h->task);
        if (state == JS_PROMISE_REJECTED) { fail(h, "promise_rejected"); return -1; }
        if (state != JS_PROMISE_PENDING) {
            if (h->modulePhase) {
                JS_FreeValue(h->context, h->task);
                h->task = call(h, "__dgActivate", 0, nullptr);
                h->modulePhase = false;
                continue;
            }
            if (!JS_IsJobPending(h->runtime)) { h->busy = false; return 0; }
        }
        JSContext *jobContext = nullptr;
        int status = JS_ExecutePendingJob(h->runtime, &jobContext);
        if (status < 0) return capture(h);
        if (!status) return 1;
        if (interrupt(h->runtime, h)) return -1;
    }
    return 1;
}

extern "C" int dgjs_dispatch(DGJSHost *h, const char *kind, const char *payload) {
    if (!h->active || h->stopped.load() || strlen(payload) > 65536) return -1;
    h->deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(250); h->busy = true; h->jobs = 0;
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
    if (!h->busy) {
        h->deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
        h->jobs = 0;
        h->busy = true;
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
