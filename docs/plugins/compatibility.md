# compatibility and verification status

schema 1 and sdk 1.0.0 accept apiVersion 1.0.0 or ^1.0.0. the initial minimum client is 13.2; ios minimum is 15.0. types describe bootstrap methods, while native capability discovery describes actual availability. a method must still reject when unavailable or revoked. opaque draft revisions are strings; they are not counters the plugin may increment.

runtime uses the vendored quickjs-ng fork. the lock hashes its actual source files and preserves the existing widget runtime's default dynamic-compilation policy. the plugin context opts into blocked eval and all function constructors. loaded source is verified package content; quickjs bytecode, node modules and downloaded executable source are not accepted.

| area | verification available in this environment |
|---|---|
| interpreter limits and callbacks | compiled native c/c++ fixtures against the real vendored quickjs engine on windows |
| static authoring tools | 26 python tests for parser, manifest/profile policy, zip paths/links/header mismatches, quotas, canonical vectors, deterministic packaging, wrappers, unavailable contracts and examples |
| example logic | eight packaged examples exercised through node development fixtures, including native controls, public-response parsing and local transform patches |
| pure model/installer/runtime/host | actual production Windows libraries and portable workflows compiled/executed; no types-only installer/runtime stub in those checks |
| native page schema | actual Foundation-only schema compiled on Windows and passed 35 shared fixtures; sdk validator checks the same cases; UIKit rendering remains separate |
| Apple CryptoKit/ImageIO and native TLS | Apple platform branches require separate Apple-host compilation and integration; Windows signed packages fail explicitly when verification is unavailable |
| full ios app | requires xcode/full bazel app build; not confirmed by portable production tests |
| native screens and animations | not verified; requires simulator recordings and labelled frame evaluation |
| real accounts, settings and updates | pending native/device acceptance scenarios |

mock tests and static checks are not evidence that a screen rendered or a native operation succeeded. source adapters, actual native tests and recorded-frame evidence must be reviewed together before calling the feature complete. poll-based interruption does not guarantee a hard deadline inside every native builtin.

app-store builds do not opt into `DG_PLUGINS_SIDELOAD`; external-plugin execution is disabled there. sideload builds can opt into the interpreter, with the same broker restrictions. this configuration is not a claim of app-store approval. current distribution requirements and entitlements remain part of release review.

bootstrap/native source now includes public requests, exact-selected-message/current-chat/selected-author snapshots, selected utf8 files, telegram translation consent, interactive ordinary-message previews, local notifications and enumerated plugin-management navigation. each method still checks platform/screen context, current grants, scopes and generation; capability discovery is advisory and unavailable operations reject. this is bounded context access, not history export or arbitrary account/peer lookup.

local transform adapters expose profile empty-pane hiding and nonpinned chat-list ordering/filtering. displayLinks is a reserved type/pure-validator contract only; registration rejects feature_unavailable until a native renderer exists. client adapters are independently subject to native screen validation. native page schema supports markdown, multiline, slider, stepper and opaque raster image nodes as well as the original controls. examples and authoring types use those contracts; mock fixture success does not establish that UIKit drew them.

theme contributions select one of four fixed native accents for the plugin's own pages only, under localTokens scope; native painting remains visually unverified. bootstrap/type event names do not establish an active native publisher, and unsupported subscriptions must reject; plugin.deactivating is not advertised. other unimplemented controls/events/routes must remain absent or explicitly unavailable. the broader original task remains incomplete while required implementation work, Apple tests or recorded-frame acceptance checks are missing.
