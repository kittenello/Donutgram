# permissions and native method policy

all grants belong to an installation and account. declaration is not consent. required grants must exist before enable; optional denial leaves the plugin able to use other granted methods. permission identity is capability, scope and the sorted exact origin set. reason text is explanatory and cannot widen access. new origins, scope or capabilities require new consent. updates stop and disable previous execution. profile changes require uninstall with all-account data removal and a fresh installation.

| method family | capability and scope | native policy |
|---|---|---|
| environment, capabilities | none | bounded host facts only |
| settings | own manifest schema | typed values, bounds, enum and quota |
| storage | storage.local / pluginAccount | own installation/account, bounded keys, 5 mib total and bounded json structure |
| commands | ui.contribute / exact placement | settings, composer, selection, messageMenu or chatToolbar; slot scope checked again |
| theme snapshot | theme.read / currentTheme | appearance facts only |
| composer read/replace | composer.read or composer.transform / activeComposer | native user action, opaque current-screen handle and revision checks in adapter |
| selection | messages.selection.read / activeSelection | native user action, protected/service sources filtered before data delivery |
| network, history, peers, chat metadata | declared capabilities | feature_unavailable until bounded native adapter exists |
| navigation, files, notifications, translation, sends | declared capabilities | feature_unavailable until route, disclosure, paid-action and confirmation policies exist |
| ui transforms, theme contributions | declared capabilities | feature_unavailable until typed renderer/adapter exists |

localPrivate plugins cannot request generic public network. publicNetwork plugins cannot request private composer, selection, message, contact or file data. these restrictions apply to optional declarations as well. a selected-text external integration needs its own native confirmed-disclosure action; granting network access is not that confirmation.

javascript request envelopes carry id, method and params. extra pluginId, accountId, publisher, permissions or userConfirmed fields are not authority. raw protocol requests, selectors, native references, keychain, authorization, session management, paid operations, asset transfer, message deletion and moderation have no registry entry.

the capabilities registry reports availability rather than returning invented success. screen-dependent methods may still return unavailable or null when the required native screen is absent. an app-owned adapter receives a cancellation/validity closure; it must recheck immediately before side effects. javascript cannot create that closure or extend its lifetime. a successfully returned promise does not grant future access.
