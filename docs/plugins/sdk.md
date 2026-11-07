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
| environment | get(); host-supplied snapshot, not account identity authority |
| composer | getActiveDraft(), replaceSelection(request); native user gesture and optimistic revision required |
| selection | get(); explicit native selection snapshot, protected sources excluded |
| theme | get(); safe appearance snapshot |
| ui | toast(text), callback(handler), render(page), dispose({id}) |
| network | request(request); reserved until the host supplies the public-network broker |

bootstrap presence alone does not establish adapter support. network, history/peer reads, theme contributions, filters, notifications, sending, files, external translation and navigation must remain unavailable until their native contracts and tests exist. there are no raw mtproto methods, authorization actions, payments, server deletion or reflection APIs.

## composer

`getActiveDraft()` returns null or `{handle,revision,text,selection,entities,entitiesComplete,plainTextComplete}`. revision is an opaque string. selection offsets are utf-16 indices, matching javascript `String.slice`. `entitiesComplete:false` and `plainTextComplete:false` mean the text snapshot is incomplete for rich content; adapters must refuse edits that cannot preserve it. do not infer that an empty entities array means a plain draft is safe.

replace using `{composer:draft.handle,expectedRevision:draft.revision,range:{start,end},text}`. the optional range defaults to the captured selection. this edits the local composer through the native adapter; it does not send a message. the host compares the current draft before committing, and a stale handle/revision must fail. selection snapshots have `{text,source,entities,entitiesComplete:false}`; source is composer or message.

## native pages

`const change = api.ui.callback(async value => { ... })` creates an owned runtime callback and returns `{id,dispose()}`; callback disposal is synchronous. put `change.id` in a node's callbackId. `await api.ui.render({id,title,nodes})` uses the native renderer and rejects when unavailable. callback delivery is bound to the native installation and runtime generation, not an id supplied by another plugin.

nodes are section, text, list, button, toggle, input and select. toggle values are booleans; inputs are strings up to 4096 characters; select options are `{title,value}` with scalar json values, and selected value must equal one option. section/text/list have no callbacks. button callbacks receive null. image and slider are unavailable. pages allow at most 128 nodes, depth 6 and 64 kib json. see `schemas/ui.schema.json`; native validation remains authoritative. disposing a page and stopping the installation remove native resources.

## execution

one interpreter belongs to one plugin/account. source imports stay inside the installed package. no fetch, webview, node, standard io/os modules, arbitrary module loader, bytecode loader, timers, dynamic eval or Function constructors are supplied. pure bundled source helpers are allowed. promises, request sizes, queued jobs, callbacks, commands, cpu polling, heap and stack have limits. native interpreter flaws and native builtins without internal polls remain risks; this is not process isolation or a proof of hard preemption.

`api.ui.toast` and log/error surfaces must not become external data channels. localPrivate plugins have no arbitrary network egress. publicNetwork plugins cannot read private composer, messages or contacts. no amount of string encoding or optional permissions changes that profile boundary.
