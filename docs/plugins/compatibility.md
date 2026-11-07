# compatibility and verification status

schema 1 and sdk 1.0.0 accept apiVersion 1.0.0 or ^1.0.0. the initial minimum client is 13.2; ios minimum is 15.0. types describe bootstrap methods, while native capability discovery describes actual availability. a method must still reject when unavailable or revoked. opaque draft revisions are strings; they are not counters the plugin may increment.

runtime uses the vendored quickjs-ng fork. the lock hashes its actual source files and preserves the existing widget runtime's default dynamic-compilation policy. the plugin context opts into blocked eval and all function constructors. loaded source is verified package content; quickjs bytecode, node modules and downloaded executable source are not accepted.

| area | verification available in this environment |
|---|---|
| interpreter limits and callbacks | compiled native c/c++ fixtures against the real vendored quickjs engine on windows |
| static authoring tools | python tests for parser, manifest/profile policy, zip paths/links/header mismatches, quotas and deterministic packaging |
| example logic | node development mock fixtures for quiet-links, templates and selected-text |
| swift modules and full ios app | not verified on windows; requires xcode/full bazel app build |
| native screens and animations | not verified; requires simulator recordings and labelled frame evaluation |
| real accounts, settings and updates | pending native/device acceptance scenarios |

mock tests and static checks are not evidence that a screen rendered or a native operation succeeded. source adapters, actual native tests and recorded-frame evidence must be reviewed together before calling the feature complete. poll-based interruption does not guarantee a hard deadline inside every native builtin.

app-store builds do not opt into `DG_PLUGINS_SIDELOAD`; external-plugin execution is disabled there. sideload builds can opt into the interpreter, with the same broker restrictions. this configuration is not a claim of app-store approval. current distribution requirements and entitlements remain part of release review.

network requests, public-service translation, messages/history/peer snapshots, interactive sends, notifications, selected-file handles, arbitrary profile/chat-list transforms, theme decorations, slider and image nodes are not advertised as working examples. implement native adapters, capability/scopes and negative tests before exposing those features as available. the broader original task remains incomplete while required adapters or ios acceptance checks are missing.
