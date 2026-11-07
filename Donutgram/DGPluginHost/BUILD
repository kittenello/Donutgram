load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_configuration//:variables.bzl", "telegram_is_appstore_build")

swift_library(
    name = "DGPluginHost",
    module_name = "DGPluginHost",
    srcs = glob(["Sources/**/*.swift"]),
    defines = ["DG_PLUGINS_SIDELOAD"] if telegram_is_appstore_build == "false" else [],
    deps = [
        "//Donutgram/DGPluginModel",
        "//Donutgram/DGPluginInstaller",
        "//Donutgram/DGPluginRuntime",
    ],
    visibility = ["//visibility:public"],
)
