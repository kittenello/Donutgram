# implementation security review

review scope: production DGPluginManager, DGPluginPolicy, quickjs c host, bootstrap and static installer. the reviewer implemented model/installer but did not implement host/runtime; this is a separate review of those components, not independent evidence for the reviewer's own code.

## actionable findings

1. profile-changing updates retained account storage/settings and surviving grants. a private plugin could retain selected personal text, update to the network profile and then export historical data. reported to the primary agent; the current host rejects changes to manifest.profile before stopping or replacing an installation. `testProfileChangingUpdateCannotReadHistoricalPrivateStorage` exercises the production install path.

2. disabling changed state and persisted before stopping. a write failure skipped stop, leaving javascript executing after the user's stop request even though subsequent broker calls failed. removal had a similar ordering issue when durable marking failed. current source stops before disable persistence and also stops in the removal-persistence failure path. failure-injection checks remain required; a normal successful disable test does not cover disk failure.

3. successful native replies did not pump queued promise continuations when no activation/dispatch completion remained pending. background callbacks waited for a later dispatch and could execute during its gesture window. reported to the runtime author; a bounded idle-reply pump and production c fixture were added by that author. this report does not substitute for the primary agent observing the updated test run.

4. preview allowed larger snapshots than runtime accepted. installer was aligned to 128 entries, 4 mib total expanded data and 1 mib/file. attachment size remains 8 mib. limits are now checked before expanding each archive entry.

5. persisted storage needed a structural json quota independent of decoder coding-path depth. otherwise a value accepted in a shallow request envelope could exceed the decoder ceiling after being nested inside device/account records and prevent state recovery. model now provides iterative `validateLimits()` with depth 24 and 8192 nodes; current host source calls it before committing storage. `testDeepStorageCannotPoisonPersistedDeviceState` checks rejection through the real broker. the separate decoder ceiling is 64; it is not a substitute for storage validation.

## checks performed by this reviewer

- swift 6.4.2 compiler parsed model, installer, installer tests and host/policy tests successfully on windows.
- the actual model passed swift 6.4.2 type checking on windows.
- tree-sitter swift parsed the same files as an additional syntax check.
- the reproducible archive generator produced eight inputs, including valid deflate, traversal, case collision, expansion/count limits, nested archive, symlink and local/central crc mismatch.
- `git diff --check` reported no whitespace errors at the check point.

the apple-host XCTest targets were authored against real production methods but have not been run by this reviewer. swift parsing does not type-check apple frameworks or execute assertions. windows lacks CryptoKit/ImageIO and ios simulator verification. production c runtime checks are owned by the runtime author and require the primary agent's observed results before being reported as passed.

## negative-test coverage and limits

`DGPluginPolicyTests` covers absent forbidden method rules, unavailable adapters, gesture requirements, profile restrictions including optional declarations, exact permission identity, json bounds, and settings type/bounds/enum validation. `DGPluginHostIntegrationTests` uses real installation, grant, activation and command paths with fake platform adapters to test forged identity/methods, denied undeclared storage, slot confinement, per-installation storage, profile updates and stale native completion after disable. tests explicitly skip when the distribution compiles execution out.

still required: execute both swift XCTest targets on apple hosts; build the complete ios app; inject persistence/removal failures; exercise actual account switching and all-account removal/restart; verify sensitive-source filtering and composer revision checks in the actual screen adapter; adversarial native builtin interruption; signature/canonicalization interoperability; inspect install/update/delete screens in recorded simulator frames. generic network, history export and interactive sending remain unavailable rather than partially trusted.
