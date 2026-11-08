load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

objc_library(
    name = "DGPluginCHost",
    module_name = "DGPluginCHost",
    srcs = ["CHost/DGPluginCHost.cpp"],
    hdrs = ["CHost/include/DGPluginCHost.h"],
    includes = ["CHost/include"],
    copts = ["-std=c++17"],
    enable_modules = True,
    deps = ["//third-party/quickjs-ng:quickjs"],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "DGPluginRuntime",
    module_name = "DGPluginRuntime",
    srcs = glob(["Sources/**/*.swift"]),
    deps = [":DGPluginCHost"],
    visibility = ["//visibility:public"],
)

cc_test(
    name = "DGPluginRuntimeTests",
    srcs = ["Tests/RuntimeTests.cpp"],
    deps = [":DGPluginCHost"],
    data = ["Sources/bootstrap.js"],
    copts = ["-std=c++17"],
    timeout = "short",
)

native_work_cases = [
    "join", "reverse", "sparse_sort", "regexp", "replace", "sort",
    "typed_sort", "regexp_linear", "stringify", "parse", "repeat", "trim",
    "bigint", "pending_storm", "pure_promise", "caught_join", "native_wait",
    "wait_cancel", "detached_wait", "cumulative_active", "descheduled", "cpu_window", "stop_join", "stop_regexp",
    "compile", "wrappers", "transforms", "transform_limit", "transform_error", "transform_denial", "rejection_getter", "default_policy",
]

[
    cc_test(
        name = "NativeWork_" + case,
        srcs = ["Tests/NativeWorkTests.cpp"],
        deps = [":DGPluginCHost"],
        data = ["Sources/bootstrap.js"],
        args = [case],
        copts = ["-std=c++17"],
        timeout = "short",
    )
    for case in native_work_cases
]

test_suite(
    name = "DGPluginNativeWorkTests",
    tests = [":NativeWork_" + case for case in native_work_cases],
    visibility = ["//visibility:public"],
)
