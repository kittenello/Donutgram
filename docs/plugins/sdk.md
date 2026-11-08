# plugin sdk 1.0.0

`Donutgram/DGPluginSDK/types/index.d.ts` describes the actual bootstrap api. include the types through your typescript configuration; the installed package contains plain javascript source, not typescript or npm dependencies. `definePlugin(manifest, implementation)` and `definePlugin(implementation)` both work; package metadata comes exclusively from the installer's static manifest, never from this function's arguments.

all native operations return promises. `api.commands.register({id,title,placement,run})` registers after the broker accepts the descriptor and returns an asynchronous disposable. the supported placements are settings, composer, selection, messageMenu and chatToolbar; the manifest must request `ui.contribute` for the actual placement. host availability and native entry points determine which placements are usable in a particular client.

`api.capabilities.list()` reports the host registry. `api.capabilities.has(name)` checks the current capability. a declared permission is not a grant, and a grant does not make an unimplemented adapter available. denied or unavailable operations reject with an error containing a code. handle `permission_denied`, `scope_denied`, `gesture_required`, `feature_unavailable`, `cancelled`, `quota_exceeded` and stale composer revisions explicitly. feature discovery is advisory; every native call is checked again.

## available bootstrap families

| family | contract |
|---|---|
| commands | register descriptor plus run handler; dispose removes native contribution |
| events | on(name,handler), disposable; native host only publishes approved event names |
| storage | get, set, remove, keys; plugin/account namespace, json values only |
| settings | get(), set(values); schema-validated persisted values |
| capabilities | has(name), list() |
| environment | get(); activation-time clientVersion/locale/appearance/lowPowerMode snapshot, not account identity authority |
| composer | getActiveDraft(), replaceSelection(request); native user gesture and optimistic revision required |
| selection | get(); explicit native selection snapshot, protected sources excluded |
| theme | get(); safe appearance snapshot; contribute({accent}), clear() for the plugin's own pages |
| ui | toast(text), callback(handler), render(page), dispose({id}) |
| network | request({url,method?}); publicNetwork profile, exact declared https origins, GET/HEAD, bounded passive utf8 response |
| messages/chats/peers | read selected message/current chat/selected author snapshots through explicit native context; no history enumerator |
| files | native pick() and read({handle}); bounded expiring utf8 text handle, no arbitrary path |
| translation | request({targetLanguage,text?}); exact current selection, named telegram service and native consent |
| navigation | open({screen:"plugins"}); the supported route is enumerated |
| notifications | local({text}); publicNetwork profile, native consent, no private-data profile |
| assets | image({path}); immutable installed raster becomes an opaque runtime-owned handle |
| actions.messages | prepare({text}), sendInteractive({handle}), compose({text}); immutable native recipient/content preview and paid-recipient denial |
| transforms | register({id,slot,priority?}, handler); bounded profile/chatList/displayLinks input and declarative patch |

bootstrap presence alone does not establish adapter support. native adapters can be missing on a platform, distribution, screen or permission scope; a declared method can still reject with feature_unavailable. the current readers are intentionally bounded to the native user's selected context, not arbitrary messages, chat ids or contact lists. the current translation service is telegram. there are no raw mtproto methods, authorization actions, payments, server deletion or reflection APIs.

events deliver `{id,timestamp,version:1,data}`; timestamp is seconds. advertised names are plugin.activated, account.contextChanged, app.foreground, theme.changed, locale.changed, chat.opened, chat.closed, composer.changed and message.observed. use id for idempotency when needed, and never interpret an event as a new permission. an event's data is filtered before delivery and requires the corresponding read grant. environment.get() returns the supplied activation snapshot; event payloads describe later changes. unsupported subscriptions reject: app.background, powerSaving.changed, plugin.deactivating, message.edited, message.deleted, selection.changed and network.reachabilityChanged have no current publisher contract. stop always invalidates the runtime rather than waiting for a final callback.

theme.contribute accepts exactly `{accent:"blue"|"green"|"purple"|"orange"}` under `theme.contribute` with `localTokens` scope. it selects a fixed native palette for the plugin's own pages on their next render/replacement. theme.clear removes that contribution. this does not alter another plugin's pages, account theme or security screens. the host owns palette tokens; author pages cannot supply the reserved __dgThemeTokens field. native painting still requires ios visual verification.

## composer

`getActiveDraft()` returns null or `{handle,revision,text,selection,entities,entitiesComplete,plainTextComplete}`. revision is an opaque string. selection offsets are utf-16 indices, matching javascript `String.slice`. `entitiesComplete:false` and `plainTextComplete:false` mean the text snapshot is incomplete for rich content; adapters must refuse edits that cannot preserve it. do not infer that an empty entities array means a plain draft is safe.

replace using `{composer:draft.handle,expectedRevision:draft.revision,range:{start,end},text}`. the optional range defaults to the captured selection. this edits the local composer through the native adapter; it does not send a message. the host compares the current draft before committing, and a stale handle/revision must fail. selection snapshots have `{text,source,entities,entitiesComplete:false}`; source is composer or message.

## native pages

`const change = api.ui.callback(async value => { ... })` creates an owned runtime callback and returns `{id,dispose()}`; callback disposal is synchronous. put `change.id` in a node's callbackId. `await api.ui.render({id,title,nodes})` uses the native renderer and rejects when unavailable. callback delivery is bound to the native installation and runtime generation, not an id supplied by another plugin.

nodes are section, text, markdown, list, button, toggle, input, multiline, select, slider, stepper and image. only section/list have children. display titles are at most200 utf-16 units and display text/input values at most4096. toggle values are booleans; select options are `{title,value}` with at most32 typed scalar choices, and selected value must equal one option. omitted select value means null and requires a null option. button callbacks receive null. noninteractive nodes have no callbacks.

slider/stepper require finite minimum, maximum, step and value: abs bounds at most1e9, minimum<maximum,0<step<=range, at most1e6 steps and a value aligned to step within1e-6. image.asset is an opaque handle obtained from assets.image, never a URL or package path. limited markdown formats headings, emphasis, inline code and lists; markdown links remain passive labels. no html, css or webview is inserted.

pages allow at most128 total nodes, nesting depth0..6 and64KiB encoded json. ids are unique across the tree; callbacks, images and page lifetimes are bound to the runtime generation. schema structural constraints are in `schemas/ui.schema.json`; native-only relational and utf-16 constraints are listed in its `x-nativeConstraints`. run `dgplugin validate-ui page.json` for those additional checks. standard JSON Schema maxLength counts Unicode code points, so the cli/native validator is required to enforce utf-16 units. disposing a page, closing its native screen or stopping the installation removes owned resources; re-render the same page id for a reviewed replacement.

## local view transforms

`api.transforms.register({id,slot,priority?}, handler)` returns an async disposable. priority is an integer from-100 through100 and at most8 transforms are registered per runtime. permissions are exactly `ui.transform` with the same slot. localPrivate profile is required. callbacks receive isolated snapshots; return only the documented patch and handle revocation/errors. host computation is asynchronous and the native layout uses its cached result/fallback rather than waiting for javascript.

profile input is `{panes:[{id,empty}]}` and patch is `{hide:[id]}`; only known panes marked empty can be hidden. chatList input is `{items:[{handle,title,unread,pinned}]}` and patch is `{order?:[handle],hidden?:[handle]}`; pinned or unknown handles cannot be moved/hidden, omitted entries keep their stable relative order. displayLinks input/patch types are reserved (`{items:[{handle,title,url}]}` / `{labels:[{handle,text}]}`); the pure validator preserves URLs, but registration currently rejects feature_unavailable because no native renderer is attached. inputs/results are bounded to32KiB and shallow typed models. multiple transforms run in deterministic order with native validation between them; a failed transform falls back safely. these methods do not mutate server folders, messages, peer data or app security screens.

## public requests

network.request accepts exactly `{url,method?:"GET"|"HEAD"}`; request headers, cookies, credentials, uploads and arbitrary bodies are not exposed. result is `{url,status,headers,body}`, with body as passive utf8 text. exact origins, public numeric endpoints, TLS hostname verification, no redirects and request/response/deadline quotas are enforced by the native broker described in network.md. a public integration cannot combine this with optional private composer/selection/message/peer/transform permissions. copying a public response into javascript never makes it executable installed source.

## execution

one interpreter belongs to one plugin/account. source imports stay inside the installed package. no fetch, webview, node, standard io/os modules, arbitrary module loader, bytecode loader, timers, dynamic eval or Function constructors are supplied. pure bundled source helpers are allowed. promises, request sizes, queued jobs, callbacks, commands, cpu polling, heap and stack have limits. native interpreter flaws and native builtins without internal polls remain risks; this is not process isolation or a proof of hard preemption.

`api.ui.toast` and log/error surfaces must not become external data channels. localPrivate plugins have no arbitrary network egress. publicNetwork plugins cannot read private composer, messages or contacts. no amount of string encoding or optional permissions changes that profile boundary.
