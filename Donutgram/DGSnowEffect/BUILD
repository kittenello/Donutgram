load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DGSnowEffect",
    module_name = "DGSnowEffect",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display:Display",
        "//Donutgram/DGSimpleSettings:DGSimpleSettings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
