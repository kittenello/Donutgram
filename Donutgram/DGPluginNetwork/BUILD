load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "DGPluginNetwork",
    module_name = "DGPluginNetwork",
    srcs = glob(["Sources/**/*.swift"]),
    deps = ["//Donutgram/DGPluginModel"],
    visibility = ["//visibility:public"],
)

swift_test(
    name = "DGPluginNetworkTests",
    srcs = ["Tests/DGPluginNetworkTests.swift"],
    deps = [":DGPluginNetwork", "//Donutgram/DGPluginModel"],
)
