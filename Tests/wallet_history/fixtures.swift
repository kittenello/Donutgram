enum WalletContext {
    struct Transaction: Equatable, Sendable {}
    enum SynchronizationError: Equatable, Sendable { case network }
    enum Phase { case restoring, creating, empty, wallet, failed }
    struct State {
        let phase: Phase
        let transactions: TransactionsState
    }
    struct TransactionsState {}
}

func history(loaded: Bool = false, failed: Bool = false) -> WalletContext.TransactionsState {
    return WalletContext.TransactionsState(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: failed ? .network : nil, hasLoaded: loaded)
}

func verify(_ phase: WalletContext.Phase, loaded: Bool = false, failed: Bool = false, expected: WalletHistoryContentState) {
    let state = WalletContext.State(phase: phase, transactions: history(loaded: loaded, failed: failed))
    precondition(WalletHistoryContentState.resolve(state: state, hasVisibleTransactions: false) == expected)
    precondition(WalletHistoryContentState.resolve(state: state, hasVisibleTransactions: true) == .items, "cached transactions must remain visible")
}

precondition(WalletHistoryContentState.resolve(state: nil, hasVisibleTransactions: false) == .loading)
let initial = WalletContext.TransactionsState(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: nil)
precondition(!initial.hasLoaded, "a newly opened wallet has not finished loading history")
verify(.wallet, expected: .loading)
verify(.wallet, failed: true, expected: .historyFailed)
verify(.wallet, loaded: true, expected: .empty)
verify(.wallet, loaded: true, failed: true, expected: .historyFailed)
verify(.restoring, expected: .loading)
verify(.restoring, failed: true, expected: .walletFailed)
verify(.restoring, loaded: true, expected: .loading)
verify(.creating, expected: .loading)
verify(.empty, expected: .intro)
verify(.empty, failed: true, expected: .historyFailed)
verify(.failed, expected: .walletFailed)
precondition(history() != history(loaded: true), "the first successful empty response must trigger a UI update")
precondition(history(loaded: true, failed: true).withError(nil) == history(loaded: true), "a recovered wallet drops the stale error and keeps what loaded")
precondition(history(loaded: true).withError(.network) == history(loaded: true, failed: true), "a failed state request keeps what loaded")
print("wallet history loading, failure, empty response and cache checks passed")

enum PasscodeError: Error { case unavailable }

final class PasscodeEnvironment {
    static let shared = PasscodeEnvironment()
    var usesDefaultKeychainAccessGroup = false
    var privateGroup: String?
    var resolutionCount = 0

    func privateAccessGroup() throws -> String {
        self.resolutionCount += 1
        guard let privateGroup else { throw PasscodeError.unavailable }
        return privateGroup
    }
}

let keychainEnvironment = PasscodeEnvironment.shared
keychainEnvironment.usesDefaultKeychainAccessGroup = true
let defaultKeychainGroup = try WalletVault.keychainAccessGroup()
precondition(defaultKeychainGroup == nil, "a sideloaded wallet must use the app's default keychain group")
precondition(keychainEnvironment.resolutionCount == 0, "the unavailable explicit group must not be resolved")
keychainEnvironment.usesDefaultKeychainAccessGroup = false
keychainEnvironment.privateGroup = "TEAM.org.telegram.test"
let explicitKeychainGroup = try WalletVault.keychainAccessGroup()
precondition(explicitKeychainGroup == keychainEnvironment.privateGroup, "regular builds keep their existing private group")
keychainEnvironment.privateGroup = nil
do {
    _ = try WalletVault.keychainAccessGroup()
    preconditionFailure("a missing private group must remain an error for regular builds")
} catch PasscodeError.unavailable {
} catch {
    preconditionFailure("unexpected keychain group resolution error")
}
print("wallet keychain group selection checks passed")
