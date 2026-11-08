# implementation security review

review scope: production DGPluginManager, DGPluginPolicy, quickjs c host, bootstrap and static installer. the reviewer implemented model/installer and later runtime hardening, while a different agent implemented the host. the host review is separate from its implementation; the overall report is not an independent audit of every subsystem or proof for the reviewer's own code.

## actionable findings

1. profile-changing updates retained account storage/settings and surviving grants. a private plugin could retain selected personal text, update to the network profile and then export historical data. reported to the primary agent; the current host rejects changes to manifest.profile before stopping or replacing an installation. `testProfileChangingUpdateCannotReadHistoricalPrivateStorage` exercises the production install path.

2. disabling changed state and persisted before stopping. a write failure skipped stop, leaving javascript executing after the user's stop request even though subsequent broker calls failed. removal had a similar ordering issue when durable marking failed. current source stops before disable persistence and also stops in the removal-persistence failure path. production portable fault-injection tests now verify those paths, native resource cancellation, failed package writes and retryable cleanup. injection exists only in the isolated DG_PLUGIN_TESTS build and is not a javascript method.

3. successful native replies did not pump queued promise continuations when no activation/dispatch completion remained pending. background callbacks waited for a later dispatch and could execute during its gesture window. reported to the runtime author; a bounded idle-reply pump and production c fixture were added by that author. this report does not substitute for the primary agent observing the updated test run.

4. preview allowed larger snapshots than runtime accepted. installer was aligned to 128 entries, 4 mib total expanded data and 1 mib/file. attachment size remains 8 mib. limits are now checked before expanding each archive entry.

5. persisted storage needed a structural json quota independent of decoder coding-path depth. otherwise a value accepted in a shallow request envelope could exceed the decoder ceiling after being nested inside device/account records and prevent state recovery. model now provides iterative `validateLimits()` with depth 24 and 8192 nodes; current host source calls it before committing storage. `testDeepStorageCannotPoisonPersistedDeviceState` checks rejection through the real broker. the separate decoder ceiling is 64; it is not a substitute for storage validation.

6. resetData cleared current state but retained the previous-version account snapshot. a later rollback could resurrect explicitly erased private storage. the host now atomically discards the rollback snapshot during reset. the real integration test resets a secret-bearing installation, rejects rollback and activates the current version only after verifying its storage is empty.

7. display-link label validation originally accepted DEL/C1 controls despite rejecting basic controls and bidi overrides. the host validator now rejects those ranges as well. real helper tests cover DEL, C1, newlines and bidi controls, reject destination-changing fields, and prove the original url remains unchanged.

8. a settled operation could still own detached native requests. a delayed promise continuation could then run during a later command's user-gesture window. the c host now drains the pending native-request set before completing the originating operation. the new isolated fixture failed before this fix and passed afterward; real host coverage verifies delayed activation cannot obtain composer access without a gesture. final-review.md records the current execution evidence and remaining platform gaps.

## checks performed by this reviewer

- swift 6.4.2 compiler parsed model, installer, installer tests and host/policy tests successfully on windows.
- the actual model passed swift 6.4.2 type checking on windows.
- tree-sitter swift parsed the same files as an additional syntax check.
- the reproducible archive generator produced eight inputs, including valid deflate, traversal, case collision, expansion/count limits, nested archive, symlink and local/central crc mismatch.
- `git diff --check` reported no whitespace errors at the check point.

the current portable production run compiled and linked actual model, installer, runtime, network helpers and host on windows and passed 36 scenario methods: 11 installer, 8 policy and 17 host integration methods. the standalone assertion/expectation adapter executes those same method bodies; it does not replace production components or claim Apple's XCTest runner integration. supplemental helpers passed confirmation-token checks, semantic versions and eight generated archive inputs. persistence fault tests and two fresh child processes passed durable removing-state recovery, stopped execution and preservation of the original document. the c engine/runtime watchdog suites passed 30 isolated cases and the original regression; existing smoke/host suites also passed. final-review.md records the latest verification scope.

apple-host XCTest targets, CryptoKit/ImageIO, the Apple network transport and ios simulator verification remain unrun here. the portable signed-package path explicitly fails unavailable when CryptoKit is absent; that is not successful Apple signature verification. Swift host compilation emitted Sendable/capture warnings in main-queue callbacks; they were reported to the primary agent and are not hidden by these passing assertions.

## negative-test coverage and limits

`DGPluginPolicyTests` covers absent forbidden method rules, unavailable adapters, gesture requirements, profile restrictions including optional declarations, exact permission identity, json bounds, and settings type/bounds/enum validation. `DGPluginHostIntegrationTests` uses real installation, grant, activation and command paths with fake platform adapters to test forged identity/methods, denied undeclared storage, slot confinement, per-installation storage, profile updates and stale native completion after disable. tests explicitly skip when the distribution compiles execution out.

the real host tests now also cover deterministic composition of two plugins, exact transform scopes, cache invalidation after stop, late patch rejection after revocation, failed-update rollback restoring previous code and storage while disabled, preservation of revoked grants, equal semver build-metadata rejection and reset/rollback erasure. pure production transform tests reject hiding nonempty panes, moving/hiding pinned chats and changing link destinations.

still required: apple-host XCTest integration; a complete ios build; actual multi-account screen switching and all-account deletion; sensitive-source filtering and composer revision checks in the real screen adapter; broader native helper interruption audits; signature/canonicalization interoperability; Apple transport verification; recorded simulator frames for install/update/delete and transform visuals. availability must follow the currently implemented native adapter, not an older staged capability table or these windows-only results.
