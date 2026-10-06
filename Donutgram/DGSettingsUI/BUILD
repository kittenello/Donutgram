load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DGSettingsUI",
    module_name = "DGSettingsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/UIKitRuntimeUtils",
        "//submodules/TelegramUI/Components/TabBarComponent:TabBarComponent",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters:ComponentDisplayAdapters",
        "//Donutgram/DGSimpleSettings:DGSimpleSettings",
        "//Donutgram/DGSnowEffect:DGSnowEffect",
        "//submodules/TelegramUI/Components/ChatListTitleView:ChatListTitleView",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/SearchBarNode:SearchBarNode",
        "//submodules/AppBundle:AppBundle",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SettingsUI:SettingsUI",
        "//submodules/UndoUI:UndoUI",
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/ItemListPeerActionItem:ItemListPeerActionItem",
    ],
    visibility = [
        "//visibility:public",
    ],
)
