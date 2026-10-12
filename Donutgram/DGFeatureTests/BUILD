load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "DGFeatureTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [
        "//Donutgram/DGSimpleSettings",
        "//submodules/Postbox",
        "//submodules/TelegramCore",
        "//submodules/TextFormat",
        "//submodules/TelegramUI/Components/InteractiveTextComponent",
    ],
)

ios_test_runner(
    name = "DGFeatureTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "DGFeatureTests",
    minimum_os_version = "15.0",
    runner = ":DGFeatureTestRunner",
    deps = [":DGFeatureTestsLib"],
    visibility = ["//visibility:public"],
)
