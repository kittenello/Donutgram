#include "DGPluginCHost.h"
#include "quickjs.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
#include <thread>
#include <cstring>

struct Requests { std::vector<long long> ids; unsigned count = 0; };
static void request(void *opaque, const char *json) {
    auto *requests = static_cast<Requests *>(opaque);
    requests->count++;
    const char *id = strstr(json, "\"id\":");
    if (id) requests->ids.push_back(strtoll(id + 5, nullptr, 10));
}
static void check(bool value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static int run(const std::string &source, const std::string &bootstrap, bool stop = false) {
    Requests requests;
    DGJSHost *host = dgjs_create(request, &requests);
    check(host != nullptr, "create");
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "add");
    std::string module = "export const value = 42;";
    check(dgjs_add_file(host, "modules/test.js", reinterpret_cast<const uint8_t *>(module.data()), module.size()) == 0, "add module");
    if (stop) dgjs_stop(host);
    auto before = std::chrono::steady_clock::now();
    int status = dgjs_start(host, "main.js", bootstrap.c_str(), "{}");
    unsigned polls = 0;
    while (status > 0 && ++polls < 100000) {
        auto ids = requests.ids;
        requests.ids.clear();
        for (auto id : ids) dgjs_reply(host, id, "{\"result\":null}");
        status = dgjs_pump(host);
    }
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-before).count();
    check(ms < 3000, "bounded execution");
    dgjs_destroy(host);
    return status;
}
int main(int argc, char **argv) {
    std::ifstream stream(argc > 1 ? argv[1] : "Donutgram/DGPluginRuntime/Sources/bootstrap.js");
    std::string bootstrap((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    check(!bootstrap.empty(), "bootstrap");
    check(run("export default definePlugin({}, {async activate(api) {await api.storage.set('x', 1); await api.commands.register({id:'test',title:'test',placement:'composer',run(){}});}})", bootstrap) == 0, "async activation bridge");
    check(run("import {value} from './modules/test.js'; definePlugin({activate(){if(value!==42)throw 1;}})", bootstrap) == 0, "local module");
    check(run("import 'https://example.com/x.js'; definePlugin({activate(){}})", bootstrap) < 0, "network module denied");
    check(run("import '../x.js'; definePlugin({activate(){}})", bootstrap) < 0, "traversal denied");
    check(run("definePlugin({activate(){while(true){}}})", bootstrap) < 0, "infinite loop");
    check(run("definePlugin({async activate(){while(true)await Promise.resolve();}})", bootstrap) < 0, "microtasks bounded");
    check(run("definePlugin({activate(){let a=[];for(;;)a.push('x'.repeat(100000));}})", bootstrap) < 0, "heap bounded");
    check(run("definePlugin({activate(){try{let a=[];for(;;)a.push('x'.repeat(100000));}catch(e){}return;}})", bootstrap) < 0, "memory stop cannot be caught");
    check(run("definePlugin({activate(){function recurse(){recurse()}recurse()}})", bootstrap) < 0, "stack bounded");
    check(run("definePlugin({activate(){}})", bootstrap, true) < 0, "cancellation");
    const char *constructors[] = {"Function", "(()=>{}).constructor", "(async()=>{}).constructor", "(function*(){}).constructor", "(async function*(){}).constructor"};
    for (auto constructor : constructors) {
        std::string source = "definePlugin({activate(){let blocked=false;try{(" + std::string(constructor) + ")('return 1')}catch(e){blocked=true}if(!blocked)throw 1;}})";
        check(run(source, bootstrap) == 0, "constructor denied");
    }
    check(run("definePlugin({activate(){let n=0;try{eval('1');n++}catch(e){}try{(0,eval)('1');n++}catch(e){}if(n)throw 1;}})", bootstrap) == 0, "eval denied");
    JSRuntime *rt = JS_NewRuntime(); JSContext *ctx = JS_NewContext(rt);
    const char *normal = "Function('return 42')()";
    JSValue result = JS_Eval(ctx, normal, strlen(normal), "test", JS_EVAL_TYPE_GLOBAL);
    int32_t value = 0; JS_ToInt32(ctx, &value, result);
    check(value == 42, "default engine policy unchanged");
    JS_FreeValue(ctx, result); JS_FreeContext(ctx); JS_FreeRuntime(rt);
    Requests requests;
    DGJSHost *host = dgjs_create(request, &requests);
    std::string source = "definePlugin({activate(){},commands:[]});";
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "cancel fixture");
    check(dgjs_start(host, "main.js", bootstrap.c_str(), "{}") == 0, "start empty");
    check(dgjs_dispatch(host, "command", "{\"id\":\"missing\"}") == 0 && dgjs_rejection(host) && strcmp(dgjs_rejection(host), "command_not_found") == 0, "unknown command rejects with its code");
    check(dgjs_dispatch(host, "event", "{\"name\":\"theme.changed\",\"payload\":{}}") == 0 && !dgjs_rejection(host), "a rejected command leaves the runtime usable");
    dgjs_destroy(host);
    requests = Requests{};
    host = dgjs_create(request, &requests);
    source = "definePlugin({activate(api){api.storage.get('x').then(()=>api.storage.set('reply',42));}});";
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "idle reply fixture");
    check(dgjs_start(host, "main.js", bootstrap.c_str(), "{}") == 2, "detached operation remains in its activation wait");
    check(requests.count == 1, "detached request");
    std::this_thread::sleep_for(std::chrono::milliseconds(1100));
    check(dgjs_reply(host, requests.ids.front(), "{\"result\":null}") == 0, "idle reply starts fresh bounded slice");
    check(dgjs_pump(host) == 2 && requests.count == 2, "detached continuation runs in originating activation without dispatch");
    check(dgjs_reply(host, requests.ids.back(), "{\"result\":null}") == 0 && dgjs_pump(host) == 0, "activation completes after detached work drains");
    dgjs_destroy(host);
    requests = Requests{};
    host = dgjs_create(request, &requests);
    source = "definePlugin({activate(api){api.ui.callback(async value=>{await api.storage.set('ui',value)});}});";
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "ui callback fixture");
    check(dgjs_start(host, "main.js", bootstrap.c_str(), "{}") == 0, "ui callback activation");
    check(dgjs_dispatch(host, "ui", "{\"id\":\"callback.1\",\"value\":42}") > 0, "ui callback invokes async native operation");
    check(requests.count == 1, "ui callback delivered");
    check(dgjs_reply(host, requests.ids.front(), "{\"result\":null}") == 0 && dgjs_pump(host) == 0, "ui callback settled");
    dgjs_destroy(host);
    host = dgjs_create(request, &requests);
    source = "definePlugin({activate(){for(;;){}}});";
    check(dgjs_add_file(host, "main.js", reinterpret_cast<const uint8_t *>(source.data()), source.size()) == 0, "cancel running fixture");
    std::thread stopper([host] { std::this_thread::sleep_for(std::chrono::milliseconds(30)); dgjs_stop(host); });
    auto before = std::chrono::steady_clock::now();
    check(dgjs_start(host, "main.js", bootstrap.c_str(), "{}") < 0, "stop while executing");
    stopper.join();
    check(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-before).count() < 500, "immediate cancellation");
    dgjs_destroy(host);
    puts("runtime tests passed");
}
