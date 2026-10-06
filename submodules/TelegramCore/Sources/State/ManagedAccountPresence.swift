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
    
    private var wasOnline: Bool = false
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
                self.requestOfflinePresence()
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

    private func requestOfflinePresence() {
        guard !self.resolvingInitialPresence else { return }
        // The request may have been queued before ghost mode was turned off.
        let ghost = DGSimpleSettings.shared
        guard ghost.ghostModeEnabled && ghost.ghostAutomaticOffline else { return }
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
                    self?.requestOfflinePresence()
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
