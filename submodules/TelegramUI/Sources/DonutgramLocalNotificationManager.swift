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
/// it receives into notifications. Only the messages Telegram would notify about arrive here: muted chats,
/// already-read messages and service migrations are filtered out by `messagesForNotification`.
///
/// The primary account's messages are notified only in the background, because `ApplicationContext` shows its
/// in-app banner in the foreground. Other accounts have no in-app banner, so theirs are notified always and
/// `AppDelegate.willPresent` lets them appear over the app.
final class DonutgramLocalNotificationManager {
    /// One catch-up after a long suspension can carry many messages; past this many only the newest are shown.
    private static let maxNotificationsPerBatch = 20

    private var inForeground: Bool = false
    private var inForegroundDisposable: Disposable?
    private let accountsDisposable = MetaDisposable()
    private let messageDisposables = DisposableDict<AccountRecordId>()
    private var subscribedAccountIds = Set<AccountRecordId>()

    init(sharedContext: SharedAccountContext, inForeground: Signal<Bool, NoError>) {
        self.inForegroundDisposable = (inForeground
        |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.inForeground = value
        })

        self.accountsDisposable.set((sharedContext.activeAccountContexts
        |> deliverOnMainQueue).start(next: { [weak self] primary, accounts, _ in
            guard let self else {
                return
            }
            var currentIds = Set<AccountRecordId>()
            for (accountId, context, _) in accounts {
                currentIds.insert(accountId)
                if self.subscribedAccountIds.contains(accountId) {
                    continue
                }
                self.subscribedAccountIds.insert(accountId)
                self.messageDisposables.set((context.account.stateManager.notificationMessages
                |> deliverOnMainQueue).start(next: { [weak self, weak context] messageList in
                    guard let self, let context else {
                        return
                    }
                    self.process(context: context, messageList: messageList)
                }), forKey: accountId)
            }
            for accountId in self.subscribedAccountIds.subtracting(currentIds) {
                self.subscribedAccountIds.remove(accountId)
                self.messageDisposables.set(nil, forKey: accountId)
            }
            self.primaryAccountId = primary?.account.id
        }))
    }

    private var primaryAccountId: AccountRecordId?

    deinit {
        self.inForegroundDisposable?.dispose()
        self.accountsDisposable.dispose()
        self.messageDisposables.dispose()
    }

    private func process(context: AccountContext, messageList: [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)]) {
        guard DGSimpleSettings.shared.backgroundNotifications else {
            return
        }
        if self.inForeground && context.account.id == self.primaryAccountId {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let contentSettings = context.currentContentSettings.with { $0 }

        var requests: [UNNotificationRequest] = []
        for (messages, _, notify, threadData) in messageList {
            guard notify, let message = messages.first else {
                continue
            }
            if let request = notificationRequest(context: context, message: message, groupSize: messages.count, threadData: threadData, presentationData: presentationData, contentSettings: contentSettings) {
                requests.append(request)
            }
        }
        if requests.count > DonutgramLocalNotificationManager.maxNotificationsPerBatch {
            requests = Array(requests.suffix(DonutgramLocalNotificationManager.maxNotificationsPerBatch))
        }
        let center = UNUserNotificationCenter.current()
        for request in requests {
            center.add(request, withCompletionHandler: { error in
                if let error {
                    Logger.shared.log("DonutgramNotifications", "add failed: \(error)")
                }
            })
        }
    }
}

private func notificationRequest(context: AccountContext, message: Message, groupSize: Int, threadData: MessageHistoryThreadData?, presentationData: PresentationData, contentSettings: ContentSettings) -> UNNotificationRequest? {
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

    let content = UNMutableNotificationContent()
    content.title = chatPeer.displayTitle(strings: strings, displayOrder: nameOrder)

    var subtitleParts: [String] = []
    if let author = message.author, author.id != chatPeer.id {
        if case let .channel(channel) = chatPeer, case .broadcast = channel.info {
        } else {
            subtitleParts.append(EnginePeer(author).displayTitle(strings: strings, displayOrder: nameOrder))
        }
    }
    if let threadData {
        subtitleParts.append(threadData.info.title)
    }
    if !subtitleParts.isEmpty {
        content.subtitle = subtitleParts.joined(separator: " → ")
    }

    if peerId.namespace == Namespaces.Peer.SecretChat {
        content.body = strings.PUSH_ENCRYPTED_MESSAGE("").string
    } else {
        let (text, _, isText) = descriptionStringForMessage(contentSettings: contentSettings, message: EngineMessage(message), strings: strings, nameDisplayOrder: nameOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: context.account.peerId)
        var body = isText ? textHidingSpoilers(message) ?? text.string : text.string
        if groupSize > 1, !isText {
            body = "\(body) (\(groupSize))"
        }
        content.body = body
    }

    content.sound = .default
    content.threadIdentifier = "\(context.account.id.int64)_\(peerId.toInt64())"
    if peerId.namespace == Namespaces.Peer.CloudChannel, case let .channel(channel) = chatPeer, case .broadcast = channel.info {
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

    // The `m<peer>:<namespace>:<id>` form lets `ClearNotificationsManager` remove it once the chat is read.
    let identifier = "m\(peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
    return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
}

/// The message text with spoilers covered, so a lock-screen notification does not reveal them.
private func textHidingSpoilers(_ message: Message) -> String? {
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
