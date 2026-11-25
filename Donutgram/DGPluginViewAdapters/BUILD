load("@build_bazel_rules_swift//swift:swift.bzl", "swift_binary", "swift_library")

swift_library(
    name = "DGPluginViewAdapters",
    module_name = "DGPluginViewAdapters",
    srcs = glob(["Sources/**/*.swift"]),
    deps = ["//Donutgram/DGPluginModel:DGPluginModel"],
    visibility = ["//visibility:public"],
)

swift_binary(
    name = "DGPluginViewAdapterChecks",
    testonly = True,
    copts = ["-parse-as-library"],
    srcs = ["Tests/ProjectionMain.swift"],
    deps = [":DGPluginViewAdapters", "//Donutgram/DGPluginModel:DGPluginModel", "//submodules/MergeLists:MergeLists"],
)
