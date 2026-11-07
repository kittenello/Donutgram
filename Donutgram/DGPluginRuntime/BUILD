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
)
