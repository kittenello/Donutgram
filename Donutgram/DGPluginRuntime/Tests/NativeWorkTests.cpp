#include "DGPluginCHost.h"
#include "quickjs.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

struct Requests {
    std::vector<int64_t> ids;
    std::atomic<bool> began{false};
};

static void check(bool value, const char *message) {
    if (!value) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}

static void request(void *opaque, const char *json) {
    auto *state = static_cast<Requests *>(opaque);
    const char *id = std::strstr(json, "\"id\":");
    check(id != nullptr, "request id");
    state->ids.push_back(std::strtoll(id + 5, nullptr, 10));
    state->began.store(true);
}

static void add(DGJSHost *host, const std::string &source) {
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "fixture source within package quota");
}

static int settle(DGJSHost *host, int status) {
    while (status == 1) { std::this_thread::sleep_for(std::chrono::milliseconds(1)); status = dgjs_pump(host); }
    return status;
}

static int compileInterrupt(JSRuntime *, void *opaque) {
    return ++*static_cast<unsigned *>(opaque) >= 5;
}

int main(int argc, char **argv) {
    check(argc >= 2, "one scenario per watchdog child process");
    std::string name = argv[1];
    std::ifstream file(argc > 2 ? argv[2] : "Donutgram/DGPluginRuntime/Sources/bootstrap.js");
    std::string bootstrap((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    check(!bootstrap.empty(), "bootstrap available");
    auto start = std::chrono::steady_clock::now();
    if (name == "default_policy") {
        JSRuntime *runtime = JS_NewRuntime();
        JSContext *context = JS_NewContext(runtime);
        std::string source = "if(Array.prototype.join.call({length:8000001},'')!=='')throw 1; if(Function('return 42')()!==42)throw 2;";
        JSValue result = JS_Eval(context, source.c_str(), source.size(), "default.js", JS_EVAL_TYPE_GLOBAL);
        check(!JS_IsException(result) && !JS_IsStopped(runtime), "default widgets retain unlimited native-work policy and dynamic compilation");
        JS_FreeValue(context, result); JS_FreeContext(context); JS_FreeRuntime(runtime);
    } else {
        Requests requests;
        DGJSHost *host = dgjs_create(request, &requests);
        check(host != nullptr, "create production runtime");
        if (name == "native_wait" || name == "wait_cancel") {
            add(host, "definePlugin({async activate(api){await api.storage.get('wait');}})");
            check(settle(host, dgjs_start(host, "main.js", bootstrap.c_str(), "{}")) == 2, "waiting only on a real native request");
            check(requests.ids.size() == 1, "one pending native request");
            if (name == "native_wait") {
                std::this_thread::sleep_for(std::chrono::milliseconds(1200));
                check(dgjs_pump(host) == 2, "legitimate native wait preserves active execution budget");
                check(dgjs_reply(host, requests.ids.front(), "{\"result\":null}") == 0, "native reply accepted");
                check(settle(host, dgjs_pump(host)) == 0, "activation resumes after native wait longer than JS deadline");
            } else {
                dgjs_stop(host);
                check(dgjs_pump(host) < 0 && dgjs_reply(host, requests.ids.front(), "{\"result\":null}") < 0, "stop invalidates wait and late native reply");
            }
        } else if (name == "cumulative_active") {
            add(host, "definePlugin({async activate(api){await api.storage.get('a');let until=Date.now()+600;while(Date.now()<until){}await api.storage.get('b');until=Date.now()+600;while(Date.now()<until){}}})");
            check(settle(host, dgjs_start(host, "main.js", bootstrap.c_str(), "{}")) == 2, "first native wait");
            check(dgjs_reply(host, requests.ids.back(), "{\"result\":null}") == 0, "first reply");
            check(settle(host, dgjs_pump(host)) == 2, "second native wait");
            check(dgjs_reply(host, requests.ids.back(), "{\"result\":null}") == 0, "second reply");
            check(settle(host, dgjs_pump(host)) < 0 && std::strcmp(dgjs_error(host), "execution_timeout") == 0, "native waits do not reset accumulated active wall budget");
        } else if (name == "cpu_window") {
            add(host, "definePlugin({activate(api){api.ui.callback(()=>{const until=Date.now()+90;while(Date.now()<until){}})}})");
            check(dgjs_start(host, "main.js", bootstrap.c_str(), "{}") == 0, "cpu window fixture started");
            int status = 0;
            for (int i = 0; i < 80 && status == 0; ++i) status = settle(host, dgjs_dispatch(host, "ui", "{\"id\":\"callback.1\",\"value\":null}"));
            check(status < 0 && std::strcmp(dgjs_error(host), "cpu_budget_exceeded") == 0, "thread cpu is bounded across individually valid callbacks");
        } else if (name == "stop_join" || name == "stop_regexp") {
            std::string operation = name == "stop_join" ? "Array.prototype.join.call({length:7000000},'');" : "/^(a+)+$/.test('a'.repeat(30)+'!');";
            add(host, "definePlugin({activate(api){api.storage.get('begin');" + operation + "}})");
            std::thread stopper([&] {
                while (!requests.began.load()) std::this_thread::yield();
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                dgjs_stop(host);
            });
            int status = dgjs_start(host, "main.js", bootstrap.c_str(), "{}");
            stopper.join();
            check(status < 0 && std::strcmp(dgjs_error(host), "cancelled") == 0, "external stop interrupts native work while executing");
        } else if (name == "compile") {
            std::string source;
            for (int i = 0; i < 45000; ++i) source += "let a" + std::to_string(i) + "=" + std::to_string(i) + ";";
            source += "definePlugin({activate(){}});";
            JSRuntime *runtime = JS_NewRuntime();
            JSContext *context = JS_NewContext(runtime);
            unsigned polls = 0;
            JS_SetNativeWorkLimit(runtime, 8000000);
            JS_SetInterruptHandler(runtime, compileInterrupt, &polls);
            JSValue result = JS_Eval(context, source.c_str(), source.size(), "compile.js", JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
            check(JS_IsException(result) && JS_IsStopped(runtime) && polls >= 5, "module compilation polls native policy before execution");
            JS_FreeValue(context, JS_GetException(context));
            JS_FreeValue(context, result); JS_FreeContext(context); JS_FreeRuntime(runtime);
        } else if (name == "wrappers") {
            add(host, "definePlugin({async activate(api){for(const call of [()=>api.messages.read({}),()=>api.chats.metadata({}),()=>api.peers.read({}),()=>api.navigation.open({screen:'plugins'}),()=>api.notifications.local({text:'x'}),()=>api.files.pick(),()=>api.files.read({handle:'x'}),()=>api.actions.messages.prepare({text:'x'}),()=>api.actions.messages.sendInteractive({handle:'x'}),()=>api.actions.messages.compose({text:'x'}),()=>api.translation.request({text:'x',targetLanguage:'en'})]){let denied=false;try{await call()}catch(e){denied=e.code==='feature_unavailable'}if(!denied)throw Error('fake adapter success')}}})");
            int status = dgjs_start(host, "main.js", bootstrap.c_str(), "{}");
            size_t replied = 0;
            while (status > 0) {
                while (replied < requests.ids.size()) check(dgjs_reply(host, requests.ids[replied++], "{\"error\":{\"code\":\"feature_unavailable\",\"message\":\"unavailable\"}}") == 0, "wrapper error reply");
                status = dgjs_pump(host);
            }
            check(status == 0 && replied == 11, "typed wrappers propagate native errors through real bridge");
        } else {
            const std::vector<std::pair<std::string, std::string>> fixtures = {
                {"join", "Array.prototype.join.call({length:2**40},'');"},
                {"reverse", "Array.prototype.reverse.call({length:2**40});"},
                {"sparse_sort", "Array.prototype.sort.call({length:2**40});"},
                {"regexp", "/^(a+)+$/.test('a'.repeat(30)+'!');"},
                {"replace", "'a'.repeat(500000).replaceAll('a'.repeat(1024)+'b','');"},
                {"sort", "Array(500).fill('a'.repeat(200000)).sort();"},
                {"typed_sort", "new Uint8Array(1000000).sort();"},
                {"regexp_linear", "const x='a'.repeat(1<<20);for(;;)/^a+$/.test(x);"},
                {"stringify", "const x=Array(2000).fill('x');for(;;)JSON.stringify(x);"},
                {"parse", "const x='['+'0,'.repeat(2000)+'0]';for(;;)JSON.parse(x);"},
                {"repeat", "for(;;)'a'.repeat(1<<20);"},
                {"trim", "const x=' '.repeat(1<<20);for(;;)x.trim();"},
                {"bigint", "(2n**100000n).toString();"},
                {"pending_storm", "api.storage.get('wait');while(true)await Promise.resolve();"},
                {"pure_promise", "await new Promise(()=>{});"},
                {"caught_join", "try{Array.prototype.join.call({length:2**40},'')}catch(e){}"}
            };
            bool found = false;
            for (const auto &fixture : fixtures) {
                if (fixture.first != name) continue;
                found = true;
                add(host, "definePlugin({async activate(api){" + fixture.second + "}})");
                int status = settle(host, dgjs_start(host, "main.js", bootstrap.c_str(), "{}"));
                check(status < 0, "hostile native work or unresolved pure promise must fail");
                std::printf("%s: %s\n", name.c_str(), dgjs_error(host));
                check(dgjs_dispatch(host, "event", "{\"name\":\"x\"}") < 0, "stop is irreversible");
            }
            check(found, "known scenario");
        }
        dgjs_destroy(host);
    }
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
    std::printf("PASS %s %lld ms\n", name.c_str(), static_cast<long long>(elapsed));
}
