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
print("wallet history loading, failure, empty response and cache checks passed")
