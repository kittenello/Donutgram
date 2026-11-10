# donutgram plugin sdk

start with [authoring](../../docs/plugins/authoring.md), [sdk reference](../../docs/plugins/sdk.md) and [compatibility](../../docs/plugins/compatibility.md). types, strict schemas, examples and local tooling are in this directory. native installer, broker and runtime remain authoritative.

`tools/dgplugin.py validate-ui page.json` checks native page structure, UTF16 limits and relational numeric/select constraints beyond portable JSON Schema. `test <example> <fixture>` checks reviewed pure example logic with passive native/network fixtures; it is not an iOS or sandbox test.

settings schema fields stay editable while a plugin is disabled. opening a custom settings page starts a temporary local settings session: `api.environment.get()` reports `executionMode: "settings"`. register settings commands in `activate()` before doing work that requires normal execution. this session can use declared local storage, settings, packaged images and its own native UI, but cannot access chats, send messages or make network requests. chat commands, transforms and event subscriptions remain inactive. it does not enable the plugin or persist extra permission grants, and stops when its settings screen closes.
