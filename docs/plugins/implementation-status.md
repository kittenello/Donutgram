# implementation checkpoint

the original product task is unfinished. this branch is an implementation checkpoint, not a verified release.

implemented source: static manifest/package preview; bounded zip reader; signatures and safe optional icons; per-installation/account interpreter; capability broker; persistence, grants, storage and settings; bounded native pages; document-tap install; installed list/card; manual updates and removal; composer and selected-message commands. changing execution profile requires clean removal/reinstallation to prevent export of historical private storage. disabling/removing interrupts execution even when persistence fails. at most four runtimes run per account.

observed locally by the primary agent: the real c/c++ quickjs runtime suite passed after the idle-promise and ui-callback fixes; 12 sdk tests passed; the postbox import/access guard passed; all new swift sources passed the swift compiler's parse stage. the real model and runtime swift wrapper passed windows type checking with swift 6.4.2 in swift 5 mode. the host passed type checking against the real model/runtime and a temporary types-only installer shim because windows lacks CryptoKit/ImageIO. this is not a full installer/host integration build. concurrency warnings remain in that toolchain mode.

not yet implemented/available: public-network broker with pinned public dns/redirect enforcement; translation, selected-file and notification adapters; bounded message/chat/peer readers; interactive ordinary-message preparation and one-use native confirmation; profile/chat-list/display-link transforms; theme decorations; remaining declarative controls/resources; all requested example categories. the current sdk reports unavailable methods rather than successful effects. the broader original task still requires these features.

still required: full ios debug/release builds; actual swift XCTest execution; persistence/crash fault injection; update/rollback and canonical signature interoperability; real multi-account, power-saving, permission-revocation and recovery scenarios; adversarial native-builtin interruption; exhaustive source/diff review. no ios simulator or xcode is available on the current windows host. no visual or animation verification has been completed. exact planned frame checks are in visual-verification.md.

additional product follow-ups: installed card should navigate back to the updated list after successful removal; richer icon/card layout and error history; declarative page replacement/closure lifecycle; complete typed events, transforms and migration/rollback support. current updates preserve compatible settings and keep changed versions disabled for review; they do not yet implement the full migration/rollback design.

app-store execution is compile-gated out through the distribution flag. no app-store approval or entitlement clearance is claimed. no pull request has been opened or remote branch pushed for this checkpoint.
