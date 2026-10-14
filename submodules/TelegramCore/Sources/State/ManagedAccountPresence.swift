import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit
import DGSimpleSettings

private typealias SignalKitTimer = SwiftSignalKit.Timer

// Donutgram: the server shows the user online after some own actions (sending a message,
// reading a chat, ...). Ghost mode answers each of them with an offline packet (see
// DGSimpleSettings.requestGhostOffline); while the app is in front this timer backs them
// up for actions nothing reports.
private let ghostOfflineFallbackInterval: Double = 30.0

// Donutgram: the server reporting the account online is weighed this long after it arrives, so an
// action here that caused it has asked for its offline packet by then (see
// AccountPresenceManagerImpl.answerServerReportedOnline).
private let ghostServerOnlineSettleDelay: Double = 3.0
// Donutgram: an action here this long before the server reports the account online is what caused it.
private let ghostOwnActionWindow: Double = 5.0
// Donutgram: the server showing the account online again this soon after an offline packet no
// action here asked for is another session answering that packet. Telegram Desktop answers in
// a couple of round trips; the margin is for slow networks.
private let ghostOtherSessionReactionInterval: Double = 10.0

// Donutgram: whether ghost mode hides online, now and after every settings change.
func donutgramGhostHidesOnlineSignal() -> Signal<Bool, NoError> {
    return Signal<Bool, NoError> { subscriber in
        subscriber.putNext(DGSimpleSettings.shared.ghostHidesOnline)
        let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: DGSimpleSettings.shared, queue: nil, using: { _ in
            subscriber.putNext(DGSimpleSettings.shared.ghostHidesOnline)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let accountId: Int64
    private let accountPeerId: PeerId
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private let initialPresenceRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    private var offlineFallbackTimer: SignalKitTimer?
    private var settingsObserver: NSObjectProtocol?
    private var offlineRequestObserver: NSObjectProtocol?
    
    private enum GhostOfflineCause {
        case action
        case unprompted
    }

    private var wasOnline: Bool = false
    // Donutgram: the last offline packet ghost mode sent, and whether an action here asked for it.
    private var lastGhostOffline: (timestamp: Double, cause: GhostOfflineCause)?
    // Donutgram: until when (server time) another session of this account keeps it online.
    private var otherSessionOnlineUntil: Int32 = 0
    // Donutgram: the server's report of this account online waiting to be weighed.
    private var pendingServerOnline: (arrival: Double, expires: Int32, previousOffline: (timestamp: Double, cause: GhostOfflineCause)?)?
    // Donutgram: how many reports in a row came as answers to the offline packet before them.
    private var answeredOfflineReports = 0
    private var lastAcknowledgedPresenceOnline: Bool = false
    private var resolvingInitialPresence = false
    private var didResolveInitialPresence = false
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountId: Int64, accountPeerId: PeerId) {
        self.queue = queue
        self.network = network
        self.accountId = accountId
        self.accountPeerId = accountPeerId
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })

        self.settingsObserver = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: DGSimpleSettings.shared, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.queue.async { [weak self] in
                guard let self else {
                    return
                }
                // UserDefaults changes are independent from the foreground
                // signal. Re-evaluate immediately so enabling ghost mode while
                // the app is active sends an offline packet right away.
                self.updatePresence(self.wasOnline)
            }
        })
        self.offlineRequestObserver = NotificationCenter.default.addObserver(forName: DGSimpleSettings.requestOfflineNotification, object: DGSimpleSettings.shared, queue: nil, using: { [weak self] notification in
            // A request without an account is for every account.
            let requestedAccountPeerId = notification.userInfo?[DGSimpleSettings.requestOfflineAccountPeerIdKey] as? Int64
            self?.queue.async { [weak self] in
                guard let self else {
                    return
                }
                if let requestedAccountPeerId, requestedAccountPeerId != self.accountPeerId.toInt64() {
                    return
                }
                if let expires = notification.userInfo?[DGSimpleSettings.requestOfflineServerOnlineExpiresKey] as? Int32 {
                    self.answerServerReportedOnline(expires: expires)
                } else {
                    self.requestOfflinePresence(cause: .action)
                }
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.initialPresenceRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        self.offlineFallbackTimer?.invalidate()
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let offlineRequestObserver = self.offlineRequestObserver {
            NotificationCenter.default.removeObserver(offlineRequestObserver)
        }
    }

    private func recordAcknowledgedPresence(isOnline: Bool, timestamp: Int32) {
        if isOnline || self.lastAcknowledgedPresenceOnline || DGSimpleSettings.shared.lastOnlineTimestamp(accountId: self.accountId) == nil {
            DGSimpleSettings.shared.setLastOnlineTimestamp(timestamp, accountId: self.accountId)
        }
        // Repeated offline requests must keep the original last-seen time.
        self.lastAcknowledgedPresenceOnline = isOnline
    }

    private func isOtherSessionOnline() -> Bool {
        return self.otherSessionOnlineUntil > Int32(self.network.globalTime)
    }

    // The server reported this account online (`updateUserStatus`). An action here usually
    // caused it, and the offline packet hides it. But another session of the account may be
    // online: Telegram Desktop, for one, sends online again as soon as it sees the account go
    // offline. Answering that one makes the two sessions flip the status between "online" and
    // "last seen just now" as fast as the requests travel. So when the server twice in a row
    // shows the account online right after an offline packet no action here asked for, the
    // account is left to the other session until its online expires: while that session is
    // online the account is shown online anyway. One such report alone is not enough, since
    // an action here nothing reports can follow the fallback packet just as closely.
    private func answerServerReportedOnline(expires: Int32) {
        if self.isOtherSessionOnline() {
            self.otherSessionOnlineUntil = max(self.otherSessionOnlineUntil, expires)
            return
        }
        if let pending = self.pendingServerOnline {
            self.pendingServerOnline = (arrival: pending.arrival, expires: max(pending.expires, expires), previousOffline: pending.previousOffline)
            return
        }
        self.pendingServerOnline = (arrival: self.network.globalTime, expires: expires, previousOffline: self.lastGhostOffline)
        self.queue.after(ghostServerOnlineSettleDelay, { [weak self] in
            self?.settleServerReportedOnline()
        })
    }

    private func settleServerReportedOnline() {
        guard let pending = self.pendingServerOnline else {
            return
        }
        self.pendingServerOnline = nil
        if let lastGhostOffline = self.lastGhostOffline, lastGhostOffline.cause == .action, lastGhostOffline.timestamp > pending.arrival - ghostOwnActionWindow {
            // An action here showed the account online. Its offline packet covers it unless
            // the server's report came after that packet.
            if lastGhostOffline.timestamp < pending.arrival {
                self.requestOfflinePresence(cause: .unprompted)
            }
            return
        }
        if let previousOffline = pending.previousOffline, previousOffline.cause == .unprompted, pending.arrival - previousOffline.timestamp < ghostOtherSessionReactionInterval {
            self.answeredOfflineReports += 1
            if self.answeredOfflineReports >= 2 {
                self.answeredOfflineReports = 0
                self.otherSessionOnlineUntil = pending.expires
                return
            }
        } else {
            self.answeredOfflineReports = 0
        }
        self.requestOfflinePresence(cause: .unprompted)
    }

    private func requestOfflinePresence(cause: GhostOfflineCause) {
        guard !self.resolvingInitialPresence else { return }
        // The request may have been queued before ghost mode was turned off.
        let ghost = DGSimpleSettings.shared
        guard ghost.ghostModeEnabled && ghost.ghostAutomaticOffline else { return }
        // An action here may have shown the account online, so it is still answered while
        // another session is online, at the cost of one flip.
        if cause == .unprompted && self.isOtherSessionOnline() {
            return
        }
        self.lastGhostOffline = (timestamp: self.network.globalTime, cause: cause)
        let timestamp = Int32(self.network.globalTime)
        let request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            if case .boolTrue = result {
                self?.recordAcknowledgedPresence(isOnline: false, timestamp: timestamp)
            }
        }, completed: { [weak self] in
            self?.isPerformingUpdate.set(false)
        }))
    }
    
    private func updateOfflineFallbackTimer(isActive: Bool) {
        if isActive {
            if self.offlineFallbackTimer == nil {
                let timer = SignalKitTimer(timeout: ghostOfflineFallbackInterval, repeat: true, completion: { [weak self] in
                    self?.requestOfflinePresence(cause: .unprompted)
                }, queue: self.queue)
                self.offlineFallbackTimer = timer
                timer.start()
            }
        } else {
            self.offlineFallbackTimer?.invalidate()
            self.offlineFallbackTimer = nil
        }
    }

    private func updatePresence(_ isOnline: Bool) {
        let ghost = DGSimpleSettings.shared
        let effectiveOnline = isOnline && !ghost.ghostHidesOnline
        if !effectiveOnline && !self.didResolveInitialPresence && ghost.lastOnlineTimestamp(accountId: self.accountId) == nil {
            if !self.resolvingInitialPresence {
                self.resolvingInitialPresence = true
                self.onlineTimer?.invalidate()
                self.onlineTimer = nil
                // Fetch the real self status before the first offline packet.
                // Postbox deliberately replaces self presence with "online".
                // Bound the lookup so an unavailable server cannot stall it.
                self.initialPresenceRequestDisposable.set((self.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]), automaticFloodWait: false)
                |> `catch` { _ -> Signal<[Api.User], NoError> in
                    return .single([])
                }
                |> timeout(2.0, queue: self.queue, alternate: .single([]))
                |> deliverOn(self.queue)).start(next: { [weak self] users in
                    guard let self, ghost.lastOnlineTimestamp(accountId: self.accountId) == nil else { return }
                    for user in users {
                        guard case let .user(data) = user, let status = data.status else { continue }
                        switch status {
                        case let .userStatusOffline(data):
                            ghost.setLastOnlineTimestamp(data.wasOnline, accountId: self.accountId)
                        case .userStatusOnline:
                            self.lastAcknowledgedPresenceOnline = true
                        default:
                            break
                        }
                    }
                }, completed: { [weak self] in
                    guard let self else { return }
                    self.resolvingInitialPresence = false
                    self.didResolveInitialPresence = true
                    self.updatePresence(self.wasOnline)
                }))
            }
            return
        } else if self.resolvingInitialPresence {
            self.initialPresenceRequestDisposable.set(nil)
            self.resolvingInitialPresence = false
            self.didResolveInitialPresence = true
        }
        let timestamp = Int32(self.network.globalTime)
        let request: Signal<Api.Bool, MTRpcError>
        if effectiveOnline {
            self.updateOfflineFallbackTimer(isActive: false)
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            // `isOnline` is true while the app is in front: only then can the user act.
            self.updateOfflineFallbackTimer(isActive: isOnline && ghost.ghostModeEnabled && ghost.ghostAutomaticOffline)
            if ghost.ghostHidesOnline {
                self.lastGhostOffline = (timestamp: self.network.globalTime, cause: GhostOfflineCause.unprompted)
            }
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            if case .boolTrue = result {
                self?.recordAcknowledgedPresence(isOnline: effectiveOnline, timestamp: timestamp)
            }
        }, completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountId: Int64, accountPeerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, accountId: accountId, accountPeerId: accountPeerId)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
