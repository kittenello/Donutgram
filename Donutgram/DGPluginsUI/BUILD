load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DGPluginsUI",
    module_name = "DGPluginsUI",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Donutgram/DGPluginModel:DGPluginModel",
        "//Donutgram/DGPluginInstaller:DGPluginInstaller",
        "//Donutgram/DGPluginHost:DGPluginHost",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = ["//visibility:public"],
)
