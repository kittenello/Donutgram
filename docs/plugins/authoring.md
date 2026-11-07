# authoring plugins

use python 3.11+ for the standard-library tools. node is required only for the development mock host. tools do not install npm packages or download dependencies.

```sh
python Donutgram/DGPluginSDK/tools/dgplugin.py create ./my-plugin --id dev.example.my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py validate ./my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py compatibility ./my-plugin
python Donutgram/DGPluginSDK/tools/dgplugin.py pack ./my-plugin ./my-plugin.dgplugin
python Donutgram/DGPluginSDK/tools/dgplugin.py validate ./my-plugin.dgplugin
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

all examples request the exact `ui.contribute` placement alongside their data permissions. do not copy the prompt's incomplete permission list without that contribution permission. examples rely on the host's native composer/selection adapters and remain subject to client availability and manual ios verification.

```sh
python Donutgram/DGPluginSDK/tools/dgplugin.py test Donutgram/DGPluginSDK/examples/quiet-links Donutgram/DGPluginSDK/tests/quiet-links.json
python -m unittest discover -s Donutgram/DGPluginSDK/tests -v
```

`test` executes author code in a separate node development process with a mock host and a five-second process timeout. it tests commands, grants, gesture gating and draft transformations using explicit fixtures. node vm is not the production sandbox and is not a supported boundary for hostile third-party code. run this command only for code you are developing or have reviewed; it proves neither native security nor ios ui behaviour. production security tests execute the actual quickjs host.

## updates

increment version using semver, keep a stable reverse-domain id, and show changed permissions/profile/origins in changelog. a matching id or author username never proves publisher identity. installation is disabled until native consent; updates require review and preserve the previous compatible installation until commit. changed grants are never inferred from an sdk wrapper. do not depend on background execution, unsafe APIs, automatic sending or migration silently enabling a plugin.
