# donutgram plugin sdk

start with [authoring](../../docs/plugins/authoring.md), [sdk reference](../../docs/plugins/sdk.md) and [compatibility](../../docs/plugins/compatibility.md). types, strict schemas, examples and local tooling are in this directory. native installer, broker and runtime remain authoritative.

`tools/dgplugin.py validate-ui page.json` checks native page structure, UTF16 limits and relational numeric/select constraints beyond portable JSON Schema. `test <example> <fixture>` checks reviewed pure example logic with passive native/network fixtures; it is not an iOS or sandbox test.
