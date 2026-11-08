# permissions and native method policy

all grants belong to an installation and account. declaration is not consent. required grants must exist before enable; optional denial leaves the plugin able to use other granted methods. permission identity is capability, scope and the sorted exact origin set. reason text is explanatory and cannot widen access. new origins, scope or capabilities require new consent. updates stop and disable previous execution. profile changes require uninstall with all-account data removal and a fresh installation.

| method family | capability and scope | native policy |
|---|---|---|
| environment, capabilities | none | bounded host facts only |
| settings | own manifest schema | typed values, bounds, enum and quota |
| storage | storage.local / pluginAccount | own installation/account, bounded keys, 5 mib total and bounded json structure |
| commands | ui.contribute / exact placement | settings, composer, selection, messageMenu or chatToolbar; slot scope checked again |
| theme snapshot | theme.read / currentTheme | appearance facts only |
| own-page accent | theme.contribute / localTokens | four fixed native palettes; only this plugin's next page render |
| composer read/replace | composer.read or composer.transform / activeComposer | native user action, opaque current-screen handle and revision checks in adapter |
| selection | messages.selection.read / activeSelection | native user action, protected/service sources filtered before data delivery; from a message's menu it is that message's whole text |
| selected messages | messages.read / selectedChats | native user action; bounded explicitly selected snapshots, no history enumeration |
| current chat / selected authors | chats.metadata.read / selectedChats; peers.read / selectedPeers | native user action; active context only, no arbitrary identifiers |
| public requests | network.public / declaredOrigins | publicNetwork; exact granted HTTPS origin, public pinned endpoint, GET/HEAD and passive bounded data; Apple transport only |
| navigation | navigation.open / safeScreens | native user action; only screen plugins, no arbitrary URLs |
| selected text file | files.userSelected / selectedFile | native picker/user action; owned expiring utf8 handle, no paths/uploads |
| local notification | notifications.local / pluginAccount | publicNetwork only; native user action and explicit native consent |
| translation | translation.request / selectedText | native user action; exact current selection and named Telegram service consent |
| compose draft | messages.compose / chosenRecipient | native user action; review in the ordinary composer, no send |
| prepare/send interactively | messages.sendInteractive / chosenRecipient | native user action; immutable native content/recipient preview, one-use scoped token; paid recipients denied |
| send directly | messages.send / chosenRecipient | separately granted automation; active native chat, ordinary unpaid text, no per-message preview; the chat's send-as identity; with edit and delete at most five actions in ten seconds and twenty a minute |
| edit selected message | messages.edit / selectedMessages | selected native message or owned expiring handle; fresh message and native edit rights checked; plain replacement text, formatting is not kept |
| delete selected message for everyone | messages.delete / selectedMessages | selected native message or owned expiring handle; current deleteGlobally rights required, no local-only fallback |
| outgoing text interception | messages.intercept / activeComposer | beforeSend replacement/cancellation before normal enqueue; draft/chat comparison and bounded asynchronous processing |
| native page / raster | ui.contribute / settings | one owned active page, generation-bound callbacks and installed raster handles; no URLs/HTML |
| local transforms | ui.transform / profile or chatList | localPrivate; validated empty-pane/nonpinned models, cached patches, generation invalidation |
| display-link transform | ui.transform / displayLinks | reserved schema/validator contract; registration unavailable until a native renderer is attached |
| events | method-specific payload grants | bounded known native event envelopes, no event grants new authority |

localPrivate plugins cannot request generic public network. publicNetwork plugins cannot request private composer, selection, message, contact or file data. these restrictions apply to optional declarations as well. a selected-text external integration needs its own native confirmed-disclosure action; granting network access is not that confirmation.

javascript request envelopes carry id, method and params. extra pluginId, accountId, publisher, permissions or userConfirmed fields are not authority. raw protocol requests, selectors, native references, keychain, authorization, session management, paid operations, asset transfer and general moderation have no registry entry. selected-message deletion is an explicit separate grant and uses native Telegram rights.

the capabilities registry reports implementation availability rather than returning invented success. the result is advisory and does not replace consent or per-call checks. screen-dependent methods may still return unavailable or null when the required native screen is absent. an app-owned adapter receives a cancellation/validity closure; it must recheck immediately before side effects. javascript cannot create that closure or extend its lifetime. a successfully returned promise does not grant future access.

advertised events are plugin.activated, account.contextChanged, app.foreground, theme.changed, locale.changed, chat.opened, chat.closed, composer.changed and message.observed. theme/chat/composer/message payloads require their corresponding read grant. app.background, powerSaving.changed, plugin.deactivating, message.edited, message.deleted, selection.changed and network.reachabilityChanged remain unavailable; stopping a runtime is not reliable delivery of a final event.
