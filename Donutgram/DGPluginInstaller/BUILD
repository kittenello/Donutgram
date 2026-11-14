load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

objc_library(
    name = "DGPluginArchiveC",
    module_name = "DGPluginArchiveC",
    enable_modules = True,
    srcs = ["Archive/DGPluginArchive.c"],
    hdrs = ["Archive/DGPluginArchive.h"],
    includes = ["Archive"],
    sdk_dylibs = ["libz"],
)

swift_library(
    name = "DGPluginInstaller",
    module_name = "DGPluginInstaller",
    srcs = glob(["Sources/**/*.swift"]),
    deps = [":DGPluginArchiveC", "//Donutgram/DGPluginModel"],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "DGPluginInstallerTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [":DGPluginInstaller", "//Donutgram/DGPluginModel"],
)

ios_test_runner(
    name = "DGPluginInstallerTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "DGPluginInstallerTests",
    minimum_os_version = "15.0",
    runner = ":DGPluginInstallerTestRunner",
    deps = [":DGPluginInstallerTestsLib"],
    visibility = ["//visibility:public"],
)
