import Foundation
import UserNotifications
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import TelegramStringFormatting
import DGSimpleSettings

/// Posts system notifications for incoming messages that arrive over the app's own connection.
///
/// Telegram delivers message notifications through APNs. A sideloaded build is re-signed under another bundle id,
/// so those pushes never reach it, and before this nothing was shown while the app was in the background.
/// `SharedWakeupManager` keeps the connection alive there (`DonutgramBackgroundKeepAlive`); this turns the messages
/// it receives into notifications, following what the server-side push would have done:
/// - only messages `messagesForNotification` lets through arrive here (muted chats, read messages and
///   service migrations are already filtered out), and its sound and Message Preview decisions are applied;
/// - while the account is online on another device (`delayNotificationsUntil`) they arrive silently;
/// - a chat's notifications are removed once it is read, on this device or another one.
///
/// The primary account's messages are notified only in the background, because `ApplicationContext` shows its
/// in-app banner in the foreground. Other accounts have no in-app banner, so theirs are notified always and
/// `AppDelegate.willPresent` lets them appear over the app.
final class DonutgramLocalNotificationManager {
    /// One catch-up after a long suspension can carry many messages; past this many only the newest are shown.
    private static let maxNotificationsPerBatch = 20

    private final class AccountState {
        weak var context: AccountContext?
        let messagesDisposable = MetaDisposable()
        let readStateDisposable = MetaDisposable()
        /// Chats with a posted notification, and those of them seen unread since. A chat is cleared only after
        /// it was seen unread, so a reminder in Saved Messages, which never counts as unread, is not removed at once.
        var notifiedPeerIds = Set<EnginePeer.Id>()
        var seenUnreadPeerIds = Set<EnginePeer.Id>()

        init(context: AccountContext) {
            self.context = context
        }

        deinit {
            self.messagesDisposable.dispose()
            self.readStateDisposable.dispose()
        }
    }

    private var inForeground: Bool = false
    private var primaryAccountId: AccountRecordId?
    private var accounts: [AccountRecordId: AccountState] = [:]
    private var inForegroundDisposable: Disposable?
    private var accountsDisposable: Disposable?

    init(sharedContext: SharedAccountContext, inForeground: Signal<Bool, NoError>) {
        self.inForegroundDisposable = (inForeground
        |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.inForeground = value
        })

        self.accountsDisposable = (sharedContext.activeAccountContexts
        |> deliverOnMainQueue).start(next: { [weak self] primary, accounts, _ in
            guard let self else {
                return
            }
            self.primaryAccountId = primary?.account.id
            var currentIds = Set<AccountRecordId>()
            for (accountId, context, _) in accounts {
                currentIds.insert(accountId)
                if let state = self.accounts[accountId], state.context === context {
                    continue
                }
                let state = AccountState(context: context)
                self.accounts[accountId] = state
                state.messagesDisposable.set((context.account.stateManager.notificationMessages
                |> deliverOnMainQueue).start(next: { [weak self, weak context] messageList in
                    guard let self, let context else {
                        return
                    }
                    self.process(context: context, messageList: messageList)
                }))
            }
            for accountId in Array(self.accounts.keys) where !currentIds.contains(accountId) {
                self.accounts.removeValue(forKey: accountId)
            }
        })
    }

    deinit {
        self.inForegroundDisposable?.dispose()
        self.accountsDisposable?.dispose()
    }

    private func process(context: AccountContext, messageList: [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)]) {
        guard DGSimpleSettings.shared.backgroundNotifications else {
            return
        }
        if self.inForeground && context.account.id == self.primaryAccountId {
            return
        }

        var items: [(messages: [Message], threadData: MessageHistoryThreadData?)] = []
        for (messages, _, notify, threadData) in messageList {
            if notify, !messages.isEmpty {
                items.append((messages, threadData))
            }
        }
        if items.isEmpty {
            return
        }
        if items.count > DonutgramLocalNotificationManager.maxNotificationsPerBatch {
            items = Array(items.suffix(DonutgramLocalNotificationManager.maxNotificationsPerBatch))
        }

        let notifiedItems = items
        let messageIds = notifiedItems.map { $0.messages[0].id }
        let presentation = context.account.postbox.transaction { transaction -> [MessageId: (sound: PeerMessageSound, displayContents: Bool)] in
            var result: [MessageId: (sound: PeerMessageSound, displayContents: Bool)] = [:]
            for id in messageIds {
                let notification = messagesForNotification(transaction: transaction, id: id, alwaysReturnMessage: true)
                result[id] = (notification.sound, notification.displayContents)
            }
            return result
        }
        let _ = (combineLatest(presentation, context.account.stateManager.delayNotificationsUntil)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self, weak context] presentationById, delayNotificationsUntil in
            guard let self, let context else {
                return
            }
            let isOnlineElsewhere = delayNotificationsUntil.flatMap { $0 > Int32(Date().timeIntervalSince1970) } ?? false
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let contentSettings = context.currentContentSettings.with { $0 }

            var requests: [UNNotificationRequest] = []
            var notifiedPeerIds = Set<EnginePeer.Id>()
            for item in notifiedItems {
                let message = item.messages[0]
                var playsSound = !isOnlineElsewhere
                if let sound = presentationById[message.id]?.sound, case .none = sound {
                    playsSound = false
                }
                let displayContents = presentationById[message.id]?.displayContents ?? true
                if let request = donutgramNotificationRequest(context: context, message: message, groupSize: item.messages.count, threadData: item.threadData, displayContents: displayContents, playsSound: playsSound, presentationData: presentationData, contentSettings: contentSettings) {
                    requests.append(request)
                    notifiedPeerIds.insert(message.id.peerId)
                }
            }
            let center = UNUserNotificationCenter.current()
            for request in requests {
                center.add(request, withCompletionHandler: { error in
                    if let error {
                        Logger.shared.log("DonutgramNotifications", "add failed: \(error)")
                    }
                })
            }
            self.observeReadState(context: context, addingPeerIds: notifiedPeerIds)
        })
    }

    private func observeReadState(context: AccountContext, addingPeerIds peerIds: Set<EnginePeer.Id>) {
        guard let state = self.accounts[context.account.id], !peerIds.isSubset(of: state.notifiedPeerIds) else {
            return
        }
        state.notifiedPeerIds.formUnion(peerIds)
        self.updateReadStateSubscription(context: context, state: state)
    }

    private func updateReadStateSubscription(context: AccountContext, state: AccountState) {
        if state.notifiedPeerIds.isEmpty {
            state.readStateDisposable.set(nil)
            return
        }
        let accountId = context.account.id
        let items = state.notifiedPeerIds.map { TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: $0) }
        state.readStateDisposable.set((context.engine.data.subscribe(EngineDataMap(items))
        |> deliverOnMainQueue).start(next: { [weak self, weak state, weak context] counters in
            guard let self, let state, let context else {
                return
            }
            var readPeerIds = Set<EnginePeer.Id>()
            for (peerId, counter) in counters {
                if counter.isUnread {
                    state.seenUnreadPeerIds.insert(peerId)
                } else if state.seenUnreadPeerIds.contains(peerId) {
                    readPeerIds.insert(peerId)
                }
            }
            if readPeerIds.isEmpty {
                return
            }
            state.notifiedPeerIds.subtract(readPeerIds)
            state.seenUnreadPeerIds.subtract(readPeerIds)
            donutgramRemoveDeliveredNotifications(accountId: accountId, peerIds: readPeerIds)
            self.updateReadStateSubscription(context: context, state: state)
        }))
    }
}

private func donutgramNotificationRequest(context: AccountContext, message: Message, groupSize: Int, threadData: MessageHistoryThreadData?, displayContents: Bool, playsSound: Bool, presentationData: PresentationData, contentSettings: ContentSettings) -> UNNotificationRequest? {
    if DonutgramShadowBan.isHidden(message) {
        return nil
    }
    if message.restrictionReason(platform: "ios", contentSettings: contentSettings) != nil {
        return nil
    }
    for media in message.media {
        if let action = media as? TelegramMediaAction {
            if case .messageAutoremoveTimeoutUpdated = action.action {
                return nil
            } else if case .conferenceCall = action.action {
                return nil
            }
        }
    }
    guard let chatPeer = messageMainPeer(EngineMessage(message)) else {
        return nil
    }

    let strings = presentationData.strings
    let nameOrder = presentationData.nameDisplayOrder
    let peerId = message.id.peerId
    let accountPeerId = context.account.peerId
    let isBroadcast: Bool
    if case let .channel(channel) = chatPeer, case .broadcast = channel.info {
        isBroadcast = true
    } else {
        isBroadcast = false
    }

    let content = UNMutableNotificationContent()
    // As `ChatMessageNotificationItem` titles them: a reminder in Saved Messages, and a scheduled message that was sent.
    if message.flags.contains(.WasScheduled), message.author?.id == accountPeerId, chatPeer.id == accountPeerId {
        content.title = strings.ScheduledMessages_ReminderNotification
    } else {
        let title = chatPeer.displayTitle(strings: strings, displayOrder: nameOrder)
        content.title = message.flags.contains(.WasScheduled) ? "📅 \(title)" : title
    }

    var subtitleParts: [String] = []
    if let author = message.author, author.id != chatPeer.id, !isBroadcast {
        subtitleParts.append(author.id == accountPeerId ? strings.DialogList_You : EnginePeer(author).displayTitle(strings: strings, displayOrder: nameOrder))
    }
    if let threadData {
        subtitleParts.append(threadData.info.title)
    }
    if !subtitleParts.isEmpty {
        content.subtitle = subtitleParts.joined(separator: " → ")
    }

    if peerId.namespace == Namespaces.Peer.SecretChat || !displayContents {
        content.body = strings.PUSH_ENCRYPTED_MESSAGE("").string
    } else {
        let (text, _, isText) = descriptionStringForMessage(contentSettings: contentSettings, message: EngineMessage(message), strings: strings, nameDisplayOrder: nameOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: accountPeerId)
        var body = isText ? donutgramTextHidingSpoilers(message) ?? text.string : text.string
        if groupSize > 1, !isText {
            body = "\(body) (\(groupSize))"
        }
        content.body = body
    }

    if playsSound {
        // The tone Telegram's own notifications use, from the app bundle.
        if Bundle.main.url(forResource: "0", withExtension: "m4a") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "0.m4a"))
        } else {
            content.sound = .default
        }
    }
    content.threadIdentifier = "\(context.account.id.int64)_\(peerId.toInt64())"
    if isBroadcast {
        content.categoryIdentifier = "c"
    } else if peerId.namespace == Namespaces.Peer.CloudUser {
        content.categoryIdentifier = "r"
    } else if peerId.namespace != Namespaces.Peer.SecretChat {
        content.categoryIdentifier = "gr"
    }

    // The keys `AppDelegate` reads back when the notification is opened or answered.
    var userInfo: [AnyHashable: Any] = [
        "accountId": context.account.id.int64,
        "peerId": peerId.toInt64(),
        "messageId.namespace": message.id.namespace,
        "messageId.id": message.id.id
    ]
    if let threadId = message.threadId, threadData != nil {
        userInfo["threadId"] = threadId
    }
    content.userInfo = userInfo

    // The `m<peer>:<namespace>:<id>` form also lets `ClearNotificationsManager` remove it when read on this device.
    let identifier = "m\(peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
    return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
}

/// Removes this account's delivered notifications of the given chats.
private func donutgramRemoveDeliveredNotifications(accountId: AccountRecordId, peerIds: Set<EnginePeer.Id>) {
    let prefixes = peerIds.map { "m\($0.toInt64()):" }
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications(completionHandler: { notifications in
        let identifiers = notifications.compactMap { notification -> String? in
            let request = notification.request
            guard prefixes.contains(where: { request.identifier.hasPrefix($0) }) else {
                return nil
            }
            if let notificationAccountId = request.content.userInfo["accountId"] as? Int64, notificationAccountId != accountId.int64 {
                return nil
            }
            return request.identifier
        }
        if !identifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    })
}

/// The message text with spoilers covered, so a lock-screen notification does not reveal them.
private func donutgramTextHidingSpoilers(_ message: Message) -> String? {
    guard let entities = message.textEntitiesAttribute?.entities else {
        return nil
    }
    let spoilerRanges = entities.compactMap { entity -> Range<Int>? in
        if case .Spoiler = entity.type {
            return entity.range
        }
        return nil
    }
    if spoilerRanges.isEmpty {
        return nil
    }
    let text = NSMutableString(string: message.text)
    for range in spoilerRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
        let lower = min(range.lowerBound, text.length)
        let upper = min(range.upperBound, text.length)
        if lower < upper {
            text.replaceCharacters(in: NSRange(location: lower, length: upper - lower), with: "•••")
        }
    }
    return foldLineBreaks(text as String)
}
