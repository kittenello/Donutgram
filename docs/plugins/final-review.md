# final implementation review

reviewed source: the current feat/js-plugins worktree. this is an implementation review with reproducible windows checks, not a release approval or an independent audit of every component. the reviewer authored model/installer and later runtime hardening; a different agent authored the host and native screen adapters.

## finding fixed during final review

detached native promises could outlive their originating activation or callback. the c host previously completed a settled top-level task when its javascript job queue was empty even if native requests remained outstanding. a later native reply could execute an old promise continuation while a new user command had an active gesture, allowing the old continuation to borrow that gesture.

`DGPluginCHost.cpp` now completes an operation only after its task settles, javascript jobs drain and the pending native-request set is empty. detached requests remain in the same bounded native-wait operation, and overlapping dispatch is rejected. this does not grant extra execution time to active loops or pending microtask storms. the isolated `detached_wait` fixture failed before the fix and passed after it. the host integration test keeps activation in starting state until the delayed native reply drains, then verifies that its attempted composer access never reaches the native adapter.

## verified invariants

- the native broker supplies identity and generation; forged ids or unknown methods do not expose authorization, payments, destructive operations or raw native calls.
- private-data and public-network profiles are mutually exclusive across installation versions. changing profiles requires removal rather than inheriting historical private data.
- declarations, exact grants and current generations are checked before native delivery and again on completion. events require their own capability/scope and do not create a user gesture. queued events and transforms are serialized with commands; pending native replies cannot leak into a later operation.
- local transforms compose deterministically, cache validated complete models, preserve pinned/nonempty content and original link destinations, and fall back after stop or revocation. a stale asynchronous patch cannot refill the current cache.
- failed updated activation restores the previous package and compatible data while disabled. rollback intersects historical grants with current grants. explicit reset discards the historical snapshot so deleted private data cannot reappear.
- disk-failure tests exercise cancellation despite failed persistence, failed package writes and retryable removal. two fresh processes verify that durable removing-state cleanup resumes without activation and preserves the original source document.
- native helpers bind ordinary-message content to scope/recipient, expiry and one use, with paid-recipient denial. source review also verifies that the actual engine enqueue path rejects service/secret/bot/paid recipients and checks validity inside its transaction. this source finding has not been exercised against a live account.

## observed commands and results

`powershell -NoProfile -File Donutgram/DGPluginRuntime/run-tests.ps1 -BuildPath "$env:TEMP\donutgram-plugin-runtime-hardening"` rebuilt the actual vendored engine and c host, verified the canonical engine lock and embedded bootstrap, and passed the original runtime regression process, 30 separately watchdog-bounded scenarios, and the existing quickjs smoke/host suites. the latter retain the default interpreter interrupt-rate assertion. generic native work, stop during execution, native waits, accumulated active budgets, cpu windows, transforms and detached request draining are exercised. repeated linear regexp was stopped by the heap limit; that case does not establish regexp polling latency.

`powershell -NoProfile -ExecutionPolicy Bypass -File Donutgram/DGPluginTests/Portable/run-tests.ps1` compiled and linked actual model, installer, runtime, network helpers and host, then passed 36 scenario method bodies: 11 installer, 8 policy and 17 host integration cases. supplemental confirmation-token, semver, persistence-fault, fresh-process restart and eight archive-fixture checks also passed. the portable assertion adapter replaces the XCTest harness only; it does not replace production implementations. native-screen fakes deliberately delay or acknowledge only the platform operation under test.

outputs are in the temporary `donutgram-plugin-runtime-hardening` and `donutgram-plugin-portable-tests` directories. the command stdout is the execution evidence; generated binaries are not application deliverables. no test process remained running after these commands completed.

## concrete external verification still required

the full ios application has not been built in this windows environment. Apple XCTest integration, CryptoKit signature interoperability, ImageIO resource decoding, Apple Network/Security transport and real engine-to-screen effects remain unverified here. the portable signed-package path explicitly fails unavailable without CryptoKit; that is not evidence of successful Apple signature verification.

recorded simulator frames remain required for install, grants, enable/disable, update/rollback, removal, declarative controls, settings navigation, profile panes and chat-list transforms. actual account switching, message confirmation/cancellation, service/protected-source exclusions, composer rich text and undo, paid-recipient changes, file-provider reads and pending-operation cancellation must be exercised on an Apple host. the detailed scenarios are in visual-verification.md.

native interruption is cooperative. the named hostile cases pass, but unicode normalization, some internal native helpers and garbage-collection cleanup are not exhaustively audited for latency. an interpreter or image-decoder memory-corruption bug remains in the app process. optional javascript deactivate/disposable cleanup is not a prerequisite for host cancellation; it is not advertised as a completed graceful-shutdown feature. unsupported event sources and display-link rendering must remain explicitly unavailable rather than inferred from a generic transform helper.

the last portable host build emitted Swift Sendable/capture warnings around main-queue callback delivery. these were reported to the primary agent for review. successful windows checks establish only the named paths above and do not establish complete ios product readiness.
