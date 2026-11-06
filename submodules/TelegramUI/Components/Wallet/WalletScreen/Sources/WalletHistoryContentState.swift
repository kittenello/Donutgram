import WalletContext

enum WalletHistoryContentState: Equatable {
    case loading
    case walletFailed
    case historyFailed
    case intro
    case empty
    case items

    static func resolve(state: WalletContext.State?, hasVisibleTransactions: Bool) -> Self {
        if hasVisibleTransactions {
            return .items
        }
        guard let state else {
            return .loading
        }
        if case .failed = state.phase {
            return .walletFailed
        }
        if state.transactions.error != nil {
            if case .restoring = state.phase {
                return .walletFailed
            }
            return .historyFailed
        }
        switch state.phase {
        case .empty:
            return .intro
        case .restoring, .creating:
            return .loading
        case .wallet:
            return state.transactions.hasLoaded ? .empty : .loading
        case .failed:
            return .walletFailed
        }
    }
}
