# implementation checkpoint

the original product task is unfinished. this branch is an implementation checkpoint, not a verified release.

## implemented source

- static manifest/document preview without execution; bounded stored/deflated zip reader; Apple Ed25519 verification and optional safe raster decoding; immutable verified package snapshots.
- separate account/installation quickjs runtimes, capability/profile/scope/gesture checks, exact grants, own storage/settings, cancellation and generation invalidation; at most four running runtimes per account. account switch, backgrounding, power saving, disable and removal stop execution.
- document-tap native installation review, disabled initial installation, installed list/card, settings, redacted diagnostics, publisher blocking, reset, reviewed updates, previous-version rollback and durable removal/recovery. profile-changing updates are rejected; removal and clean reinstall are required.
- native composer/selection commands and bounded selected-message/current-chat/selected-author snapshots; selected utf8 files, Telegram translation consent, native ordinary-message preview with single-use recipient-bound confirmation, local notifications and enumerated plugin-settings navigation.
- public HTTPS GET/HEAD broker with exact origins, validated numeric endpoints, original TLS hostname trust, no redirects, passive bounded responses and cancellation. Apple transport is unavailable on Windows.
- native declarative pages with twelve node families, owned callbacks, replacement/closure cleanup, installed raster handles and four fixed accents limited to the plugin's own pages. local profile empty-pane hiding and nonpinned chat-list ordering/filtering use typed validated transform patches and cached native results.
- bounded event envelopes and advertised native event sources; authoring types, strict CLI validators, deterministic packaging and seven example packages with passive development fixtures.

implementation availability still depends on platform, active native screen and grants. a wrapper or registered method is not proof that an adapter is attached or an effect occurred. displayLinks currently has a reserved schema/pure patch validator only; its registration rejects feature_unavailable until a native renderer exists. unsupported event names reject; arbitrary history/account lookup, external code downloads, raw native protocols and security/payment operations have no API.

## observed verification

the actual model, installer, runtime, public-network helpers and host were compiled and linked as Windows libraries; production installer/policy/host scenarios execute through a standalone assertion adapter rather than a types-only shim. the canonicalization run passed 37 scenario methods (12 installer, 8 policy, 17 host), plus semantic-version, native confirmation-token and hostile archive helpers. production persistence fault injection and fresh child-process recovery checks passed. see portable-verification.md and security-review.md for exact paths and limits. subsequent host edits still require their final regression run.

the real quickjs c/c++ runtime/watchdog suite passed the recorded hostile callback, cancellation, promise and native-builtin cases; runtime-hardening.md defines that coverage and remaining poll-based interruption limits. the final SDK source audit passed 26 tests, including canonical vectors, unavailable event/display-link rejection and explicit non-attestation of package signatures; the actual Foundation-only native page schema again passed 35 shared valid/invalid fixtures. those checks do not draw UIKit. later audit results must be recorded with their actual run rather than inferred from these counts.

Windows uses native BCrypt SHA256 with known vectors and fails signed packages explicitly when CryptoKit is absent. it does not validate Apple Ed25519, ImageIO or Network/Security branches. standalone scenario execution also does not prove Apple XCTest runner integration.

## remaining acceptance work

full ios debug/release builds, Apple XCTest integration, Apple DNS/TLS transport tests and Apple signed-package interoperability remain required. signatures now require dg-canonical-v1 tagged binary manifest encoding instead of platform JSONEncoder output. production Swift canonicalization is checked against Python binary/hash vectors and an externally signed fixture is included for the Apple installer tests; Apple Ed25519 execution remains pending. the SDK currently validates packages but does not sign or attest their signatures. authoring.md specifies the complete byte grammar and payload.

real native-screen checks remain for sensitive-source filtering, composer revision/entity preservation, selected-file/translation/send consent, paid-recipient denial, multi-account switching, revocation and recovery. simulator recordings with labelled frames are required for cards, installation/update/removal, page controls, theme accents and local transforms; none has been recorded on this Windows host. visual-verification.md lists planned checks. persistence tests cover selected injected failures, not exhaustive crash/fault coverage, and general schema/data migration remains limited to compatible reviewed updates and rollback.

additional adversarial review is still required for the full integrated diff and native helper interruption. Swift 5 mode on Swift 6.4.2 emits concurrency warnings in main-queue callback paths; passing tests do not resolve those warnings. a DNS resolver worker can outlive a cancelled request because getaddrinfo has no cancellation here; request completion and connection creation remain deadline/generation guarded.

app-store execution is compile-gated out through the distribution flag. no app-store approval or entitlement clearance is claimed. no pull request has been opened or remote branch pushed for this checkpoint.
