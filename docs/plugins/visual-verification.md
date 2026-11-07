# plugin ui verification

status: pending. this windows environment has no xcode, ios simulator, xcodebuildmcp or recorded simulator frames. source parsing and successful non-ui tests do not verify appearance, navigation or animation.

## intended frames, before recording

the plugins row appears in the extensions group and reflects the running count or global stop. the grouped plugin list contains search, the global execution switch, author/version/state and separate enable switches. tapping a title or picture opens details; toggling only changes enablement. returning keeps the list position. long names, descriptions, permission reasons, digests and service origins must wrap without clipping or horizontal overflow. dark and light themes keep readable contrast.

opening a telegram plugin document shows a checking page, then a native full-screen installation card. neither page executes javascript. the same metadata component appears after installation. unsigned authors remain explicitly unverified. installation starts disabled; the optional enable-after-install switch starts off. choosing it routes through explicit permission grants before activation. required and optional permissions remain distinguishable and exact scopes/origins stay visible.

the document preview icon changes only after a completed telegram resource passes static validation. no external icon url is loaded and no javascript runs. malformed plugin files retain the ordinary document icon. a valid missing or broken optional icon uses deterministic initials. resource parsing and image decoding run off the chat layout queue. cached icons are keyed by package digest, so an update cannot retain the previous image by id alone.

enabling, disabling, granting/revoking rights, account switching, global stopping, failure and quarantine must update the list and details consistently. no row reports running before activation succeeds. a stale rendered page cannot invoke callbacks after stop or permission revocation.

the removal confirmation names the plugin and explains that all of its accounts' local data on this device is removed. cancelling changes nothing. confirmed removal leaves an unavailable detail state and an updated list; returning uses the original list controller. resetting data has its own confirmation and applies only to the current account.

## recordings required

- settings entry, search by name/author/id, empty results and keyboard dismissal;
- valid single-file and archive documents, cancellation before install, unsigned/signed metadata, malformed/incompatible files and oversized documents;
- missing/broken icons, long content, light/dark appearance and large accessibility text;
- install disabled, enable-after-install with required/optional grants, denied grants and activation failure;
- same-version/downgrade rejection, update changelog, changed profile/scopes/origins and newly requested permissions;
- enable/disable from list and details, global stop, permission revoke, reset confirmation and both removal paths;
- old/new accounts while an operation is pending, and foreground/background transitions;
- declarative plugin pages, every supported control and cancellation while a callback is pending.

record each touched open/close path in real time using `xcrun simctl io recordVideo`, with still time on both sides. extract timestamped sheets with `tools/animation_sheet.py` and review every frame, including flagged jumps and gaps. before accepting a visual change, append the recording paths, frame/time ranges and observed defects here. no such evidence exists yet.

## implemented renderer subset

section, text, list, button, toggle, input and select use the same native grouped-list renderer. page payloads are limited to 64 kib, 128 nodes and depth 6; ids are unique; unknown fields, invalid callback placement and control/bidirectional title characters are rejected. select options use `{title, value}` with scalar json values including null. slider and image nodes return `feature_unavailable`; they are not presented as working controls. runtime-bound validity is checked immediately before each callback. host cleanup closes the page after stop/revoke.

composer commands appear in the chat avatar menu; explicit chosen-message commands appear in the message menu. draft snapshots use opaque owner-bound handles and revisions, expire after 30 seconds and are single-use for edits. edits compare the complete original `ChatTextInputState` immediately before the existing undo-aware update closure and use `replacingFlatRange`. the snapshot exports plain text only and reports incomplete entities/structure. no send adapter exists. protected/service messages are excluded independently of user bypass settings.
