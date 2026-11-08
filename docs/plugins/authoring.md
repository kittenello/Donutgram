# authoring plugins

use python 3.11+ for the standard-library tools. node is required only for the development mock host. tools do not install npm packages or download dependencies.

```sh
python Donutgram/DGPluginSDK/tools/dgplugin.py create ./my-plugin --id dev.example.my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py validate ./my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py compatibility ./my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py pack ./my-plugin ./my-plugin.dgplugin
python Donutgram/DGPluginSDK/tools/dgplugin.py validate ./my-plugin.dgplugin
python Donutgram/DGPluginSDK/tools/dgplugin.py validate-ui ./page.json
```

create refuses an existing directory. pack writes a deterministic stored zip with fixed timestamps; review the destination before overwriting your own previous output. distribute the resulting file as a telegram document. the app's supported installation route is a tap on that document and native review. these tools do not add a url importer or automatic installation.

## formats

`.donut.js` starts with `const _plugin = "donutgram";`, immediately followed by `const manifest =` and a strict json object plus semicolon. quoted keys and strings, arrays, finite numbers, booleans and null are supported. no executable expressions, getters, spread or duplicate/reserved keys are accepted. the static parser does not run the rest of the source. ordinary `.js` files remain documents. the marker is format identification, not publisher proof.

`.dgplugin` contains manifest.json, an entry .js source beginning with the marker, and optional installed sources or raster assets. paths must be normalized relative paths without traversal, links, collisions or nested archives. runtime-compatible tool limits are 128 files, 1 mib per file and 4 mib total; header validation precedes zip member reads. signatures require the native installer's cryptographic verification; cli validation explicitly reports that it has not verified them.

`schemas/manifest.schema.json` specifies accepted fields and capability scopes. native validation additionally checks profile combinations, compatible versions, resource types and path safety. this cli intentionally uses a strict subset of the host format and stricter runtime limits. it is a development aid, not a replacement for native review or a malicious-code detector.

## examples

- quiet-links: composer command removes utm query keys from the selected http/https text. bundled `modules/clean-url.js` is a pure lexical helper; it preserves remaining query bytes and fragment, and does not open or fetch urls. it is not a full browser URL implementation.
- templates: settings contain a template string; an explicit composer command inserts it using the current handle/revision.
- selected-text: explicit selection command reports word and character counts locally, without external transfer.
- public-repository: explicit settings command reads the fixed public GitHub zlib-repository endpoint through the native public broker and displays a bounded page. it requests publicNetwork plus the exact api.github.com origin and reads no account data.
- native-controls: demonstrates all supported declarative node families, generation-local callbacks, schema settings, an own-page accent and a packaged raster obtained through an opaque asset handle. changes persist only to the plugin's own settings. its theme permission is limited to localTokens.
- profile-empty: returns a patch hiding only native profile panes marked empty. no command/contribution permission is needed because it registers only the profile transform.
- unread-first: sorts nonpinned local chat-list models with unread rows first; an own boolean setting optionally filters read rows. it never changes server folders or pinned rows.

command/page examples request the exact `ui.contribute` placement alongside needed data permissions. transform-only examples request the exact `ui.transform` slot, without unrelated commands, storage or network rights. do not copy an incomplete command permission list without its contribution permission. examples rely on the corresponding native adapters and remain subject to client availability and manual ios verification.

```sh
python Donutgram/DGPluginSDK/tools/dgplugin.py test Donutgram/DGPluginSDK/examples/quiet-links Donutgram/DGPluginSDK/tests/quiet-links.json
python -m unittest discover -s Donutgram/DGPluginSDK/tests -v
powershell -File Donutgram/DGPluginSDK/tools/check-native-pages.ps1
```

`test` executes author code in a separate node development process with a mock host and a five-second process timeout. fixtures supply commands, UI callback events, passive public responses, approved native result snapshots and typed transform inputs/expected patches. the mock makes no real network requests or native confirmations. ui.render uses the same cli page validator; production native schema checks remain independent. node vm is not the production sandbox and is not a supported boundary for hostile third-party code. run this command only for code you are developing or have reviewed; it proves neither native security nor ios ui behaviour. production security tests execute the actual quickjs host.

the public-repository fixture verifies parsing and rendering without contacting github. to test the real service on ios, grant only its declared origin, invoke its explicit command and verify the native TLS/response path separately. the native-controls fixture verifies all callbacks and persisted setting values, without claiming a screen was drawn. profile/chat-list fixtures verify the exact proposed patch and preserve pinned/nonempty entries; actual native application still needs screen-level acceptance. the windows native-page script compiles the actual Foundation-only page schema with the portable swift toolchain and checks 35 shared fixtures; it does not compile or render UIKit.

## updates

increment version using semver, keep a stable reverse-domain id, and show changed permissions/profile/origins in changelog. a matching id or author username never proves publisher identity. installation is disabled until native consent; updates require review and preserve the previous compatible installation until commit. changed grants are never inferred from an sdk wrapper. do not depend on background execution, unsafe APIs, automatic sending or migration silently enabling a plugin.

## signature format

signed archives require signature.json with exactly algorithm, canonicalization, publicKey and signature. algorithm is Ed25519 and canonicalization must be dg-canonical-v1; a missing or unknown format is rejected. publicKey is standard base64 of the 32-byte raw public key; signature is standard base64 of the 64-byte Ed25519 signature. signatures prove key possession/content integrity, not trustworthiness. the CLI does not sign or verify packages.

dg-canonical-v1 encodes the parsed manifest as tagged binary bytes, independently of JSON serialization:

| value | encoding |
|---|---|
| null | ASCII n |
| boolean | ASCII t or f |
| number | ASCII d followed by eight IEEE754 binary64 bytes in big-endian order; normalize negative zero to positive zero; reject nonfinite values |
| string | ASCII s, decimal UTF8 byte count, colon, then those UTF8 bytes; no Unicode normalization |
| array | ASCII a, decimal element count, colon, then each encoded value in order |
| object | ASCII o, decimal pair count, colon, then each encoded string key and encoded value, sorted lexicographically by the key's unsigned UTF8 bytes |

counts use minimal unsigned decimal ASCII (zero is 0). there is no whitespace, terminator or padding beyond string lengths and the fixed number width. JSON numbers are interpreted as binary64 before encoding. ordinary metadata complexity/duplicate-key validation still applies; this does not make invalid metadata valid.

the signed payload begins with ASCII `donutgram.plugin.signature.v1` plus LF. for every installed file except signature.json, sorted by its normalized ASCII package path, append `byteCount:path:sha256` plus LF. byteCount is the path's UTF8 length in minimal decimal; sha256 is lowercase 64-character hexadecimal. manifest.json is hashed as dg-canonical-v1 bytes; every other file is hashed as its exact installed bytes. Ed25519 signs the entire resulting payload, including the final LF. the archive/container bytes themselves are not the signature payload.

tests/signature-canonical-v1.json publishes nine binary/hash vectors and a package signed by Python cryptography with a temporary test key; only the public key is retained. tools/signature_fixture.py can regenerate this development fixture when that optional Python library is installed, without adding an application dependency. production Swift tests compare their real canonical bytes against those vectors. the Apple test branch verifies the externally generated signature through the real installer and rejects modified source; that branch still needs Apple-host execution. Windows explicitly rejects cryptographic verification as unavailable. these results do not yet establish complete Apple interoperability or authorize an SDK signing command.
