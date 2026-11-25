load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DGMediaTransferUI",
    module_name = "DGMediaTransferUI",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Donutgram/DGSimpleSettings",
        "//submodules/AccountContext",
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramStringFormatting",
    ],
    visibility = ["//visibility:public"],
)
