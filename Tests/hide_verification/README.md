# Hide verification

Backend for «Скрыть верификацию», the toggle in Donutgram settings → «Оформление» → «Основное» (link key `hideVerification`). The persistent flag defaults to `false`; in code:

```swift
DGSimpleSettings.shared.hideVerification = true
```

Use `Peer.donutgramDisplayIsVerified` and `Peer.donutgramDisplayVerificationIconFileId` (also available on `EnginePeer`) when drawing Telegram badges. Use `DonutgramVerificationDisplay.verification` for organization descriptions. Keep the raw `isVerified` and `verificationIconFileId` for trust checks, server actions and model copies. Donutgram developer, supporter and Baha badges bypass this filter.

`python3 Tests/hide_verification/run.py` compiles production settings, display getters and team badge lookup with minimal peer fixtures, checks off/on/off restoration and persistence in fresh processes, audits UI coverage, and parses changed Swift files. This is not an iOS build or a device test. `--source-only` runs the source audit without Swift.
