load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "DGPluginTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [
        "//Donutgram/DGPluginModel",
        "//Donutgram/DGPluginInstaller",
        "//Donutgram/DGPluginHost",
    ],
)

ios_test_runner(
    name = "DGPluginTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "DGPluginTests",
    minimum_os_version = "15.0",
    runner = ":DGPluginTestRunner",
    deps = [":DGPluginTestsLib"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "HostileFixtures",
    testonly = True,
    srcs = glob(["hostile-fixtures/**"]),
    visibility = ["//visibility:public"],
)
