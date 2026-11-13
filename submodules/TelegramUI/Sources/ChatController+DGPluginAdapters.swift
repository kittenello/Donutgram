import Foundation
import UIKit
import ObjectiveC
import UniformTypeIdentifiers
import UserNotifications
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import PresentationDataUtils
import DGPluginModel
import DGPluginHost
import DGPluginsUI
import DGPluginViewAdapters

private var dgAdditionalPluginStateKey: UInt8 = 0

private final class DGPluginAdditionalState {
    let actions = DGPluginNativeActionStore()
    var files: [String: (scope: String, text: String, expires: TimeInterval)] = [:]
    var picker: DGPluginTextPicker?
    var ownedScopes = Set<String>()
    var scopeResources: [String: () -> Void] = [:]
    var messages: [String: (scope: String, message: EngineMessage, expires: TimeInterval)] = [:]

    func releaseScopes() {
        let resources = Array(scopeResources.values)
        scopeResources.removeAll()
        for scope in ownedScopes { actions.removeAll(scope: scope) }
        ownedScopes.removeAll()
        files.removeAll()
        messages.removeAll()
        resources.forEach { $0() }
    }

    deinit {
        scopeResources.values.forEach { $0() }
        picker?.finish(.failure(DGPluginError(code: "cancelled", message: "chat closed")))
    }
}

private final class DGPluginTextPicker: NSObject, UIDocumentPickerDelegate {
    let validity: () -> Bool
    let complete: (Result<(String, String), DGPluginError>) -> Void
    private var finished = false
    weak var controller: UIDocumentPickerViewController?

    init(validity: @escaping () -> Bool, complete: @escaping (Result<(String, String), DGPluginError>) -> Void) { self.validity = validity; self.complete = complete }

    func finish(_ result: Result<(String, String), DGPluginError>) {
        guard !finished else { return }
        finished = true; controller?.dismiss(animated: true)
        complete(result)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.failure(DGPluginError(code: "cancelled", message: "file selection cancelled"))) }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard urls.count == 1, let url = urls.first, validity() else { finish(.failure(DGPluginError(code: "cancelled", message: "file selection is no longer current"))); return }
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result: Result<(String, String), DGPluginError>
            do {
                let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard metadata.isRegularFile == true, let size = metadata.fileSize, size <= 49152 else { throw DGPluginError(code: "invalid_argument", message: "selected file must be bounded regular utf8 text") }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 49153) ?? Data()
                guard data.count <= 49152, let text = String(data: data, encoding: .utf8) else { throw DGPluginError(code: "invalid_argument", message: "selected file must be bounded utf8 text") }
                result = .success((String(url.lastPathComponent.prefix(128)), text))
            } catch let error as DGPluginError { result = .failure(error) }
            catch { result = .failure(DGPluginError(code: "invalid_argument", message: "unable to read selected text file")) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.validity() else { self.finish(.failure(DGPluginError(code: "cancelled", message: "file selection is no longer current"))); return }
                self.finish(result)
            }
        }
    }
}

extension ChatControllerImpl {
    func dgPluginChatOpened() {
        guard dgPluginSafeComposer() else { return }
        DGPluginManager.shared(accountKey: String(context.account.id.int64)).emitNativeEvent(name: "chat.opened", payload: .object(["hasActiveChat": .bool(true)]))
    }

    func dgPluginChatClosed() {
        DGPluginManager.shared(accountKey: String(context.account.id.int64)).emitNativeEvent(name: "chat.closed", payload: .object(["hasActiveChat": .bool(false)]))
    }

    func dgPluginChatClosing() {
        dgPluginChatState.lifetime.close()
        dgPluginChatState.outgoingSendPending = false
        dgAdditionalPluginState.releaseScopes()
    }

    func dgPluginComposerChanged() {
        guard dgPluginSafeComposer() else { return }
        DGPluginManager.shared(accountKey: String(context.account.id.int64)).emitNativeEvent(name: "composer.changed", payload: .object(["metadataOnly": .bool(true)]))
    }

    private var dgAdditionalPluginState: DGPluginAdditionalState {
        if let state = objc_getAssociatedObject(self, &dgAdditionalPluginStateKey) as? DGPluginAdditionalState { return state }
        let state = DGPluginAdditionalState()
        objc_setAssociatedObject(self, &dgAdditionalPluginStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    private func dgPluginSelectedText(installationId: String) -> String? {
        if let message = dgPluginChatState.selectedMessages[installationId], dgPluginSafeMessage(message) { return message.text }
        guard dgPluginSafeComposer() else { return nil }
        let state = presentationInterfaceState.interfaceState.effectiveInputState
        let text = state.content.plainText as NSString
        let range = state.selectionRange
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= text.length else { return nil }
        return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    func dgHandleAdditionalPluginRequest(installationId: String, method: String, params: DGPluginJSON, validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Bool {
        let supported: Set<String> = ["messages.read", "messages.send", "messages.edit", "messages.delete", "chats.metadata", "peers.read", "navigation.open", "notifications.local", "files.pick", "files.read", "messages.prepare", "messages.sendInteractive", "messages.compose", "translation.request"]
        guard supported.contains(method) else { return false }
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        guard let scope = manager.nativeScope(installationId: installationId), validity(), isNodeLoaded, view.window != nil else { completion(.failure(DGPluginError(code: "cancelled", message: "native context is no longer active"))); return true }
        let arguments = params.objectValue ?? [:]
        let pluginName = manager.installations.first(where: { $0.id == installationId })?.manifest.name ?? dgPluginText("Плагин", "Plugin")
        if !dgAdditionalPluginState.ownedScopes.contains(scope) {
            guard let token = manager.ownNativeResource(installationId: installationId, scope: scope, cleanup: { [weak self] in
                guard let self else { return }
                self.dgAdditionalPluginState.actions.removeAll(scope: scope)
                self.dgAdditionalPluginState.files = self.dgAdditionalPluginState.files.filter { $0.value.scope != scope }
                self.dgAdditionalPluginState.messages = self.dgAdditionalPluginState.messages.filter { $0.value.scope != scope }
                self.dgAdditionalPluginState.ownedScopes.remove(scope)
                self.dgAdditionalPluginState.scopeResources.removeValue(forKey: scope)
            }) else { completion(.failure(DGPluginError(code: "quota_exceeded", message: "native scope resource limit reached"))); return true }
            dgAdditionalPluginState.ownedScopes.insert(scope)
            dgAdditionalPluginState.scopeResources[scope] = { manager.releaseNativeResource(installationId: installationId, token: token) }
        }
        do {
            switch method {
            case "messages.read":
                guard arguments.isEmpty, let message = dgPluginChatState.selectedMessages[installationId], dgPluginSafeMessage(message) else { throw DGPluginError(code: "scope_denied", message: "choose one eligible message using its native plugin action") }
                let now = ProcessInfo.processInfo.systemUptime
                dgAdditionalPluginState.messages = dgAdditionalPluginState.messages.filter { $0.value.expires >= now }
                guard dgAdditionalPluginState.messages.count < 64 else { throw DGPluginError(code: "quota_exceeded", message: "too many message handles") }
                let handle = UUID().uuidString.lowercased()
                dgAdditionalPluginState.messages[handle] = (scope, message, now + 60)
                let snapshot = DGPluginJSON.object(["handle": .string(handle), "text": .string(message.text), "timestamp": .number(Double(message.timestamp)), "entities": .array([]), "entitiesComplete": .bool(false), "mediaComplete": .bool(false)])
                manager.emitNativeEvent(name: "message.observed", payload: snapshot, installationId: installationId)
                completion(.success(.array([snapshot])))
            case "chats.metadata":
                guard arguments.isEmpty, dgPluginSafeComposer(), let peer = presentationInterfaceState.renderedPeer?.chatMainPeer else { throw DGPluginError(code: "scope_denied", message: "no eligible selected chat") }
                completion(.success(.object(["handle": .string(UUID().uuidString.lowercased()), "title": .string(String(peer.debugDisplayTitle.prefix(128))), "scope": .string("currentNativeChat") ])))
            case "peers.read":
                guard arguments.isEmpty, let message = dgPluginChatState.selectedMessages[installationId], dgPluginSafeMessage(message), let author = message.author, !author.isService else { throw DGPluginError(code: "scope_denied", message: "no eligible author selected by a native message action") }
                completion(.success(.array([.object(["handle": .string(UUID().uuidString.lowercased()), "title": .string(String(author.debugDisplayTitle.prefix(128)))])])))
            case "navigation.open":
                guard Set(arguments.keys) == ["screen"], arguments["screen"] == .string("plugins"), validity(), let navigationController else { throw DGPluginError(code: "scope_denied", message: "only an available native plugin-management route is supported") }
                navigationController.pushViewController(dgPluginsController(context: context), animated: true)
                completion(.success(.null))
            case "files.pick":
                guard arguments.isEmpty, dgAdditionalPluginState.picker == nil else { throw DGPluginError(code: "conflict", message: "a text-file chooser is already open") }
                let lifetime = dgPluginChatState.lifetime
                let chatCurrent = lifetime.snapshot()
                let pickerCurrent = { chatCurrent() && validity() }
                var token: UUID?
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .json], asCopy: true)
                let delegate = DGPluginTextPicker(validity: pickerCurrent) { [weak self, weak lifetime] result in
                    if let token {
                        lifetime?.release(token)
                        manager.releaseNativeResource(installationId: installationId, token: token)
                    }
                    guard let self else { completion(.failure(DGPluginError(code: "cancelled", message: "chat closed"))); return }
                    self.dgAdditionalPluginState.picker = nil
                    switch result {
                    case let .failure(error): completion(.failure(error))
                    case let .success((name, text)):
                        guard pickerCurrent() else { completion(.failure(DGPluginError(code: "cancelled", message: "file permission revoked or chat closed"))); return }
                        self.dgAdditionalPluginState.files = self.dgAdditionalPluginState.files.filter { $0.value.expires >= ProcessInfo.processInfo.systemUptime }
                        guard self.dgAdditionalPluginState.files.count < 4 else { completion(.failure(DGPluginError(code: "quota_exceeded", message: "too many selected file handles"))); return }
                        let handle = UUID().uuidString.lowercased()
                        self.dgAdditionalPluginState.files[handle] = (scope, text, ProcessInfo.processInfo.systemUptime + 60)
                        completion(.success(.object(["handle": .string(handle), "name": .string(name), "size": .number(Double(text.utf8.count))])))
                    }
                }
                picker.delegate = delegate; picker.allowsMultipleSelection = false; delegate.controller = picker
                token = manager.ownNativeResource(installationId: installationId, scope: scope) { [weak delegate] in delegate?.finish(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))) }
                guard let token else { throw DGPluginError(code: "quota_exceeded", message: "native resource limit reached") }
                dgAdditionalPluginState.picker = delegate
                lifetime.own(token) { [weak delegate] in delegate?.finish(.failure(DGPluginError(code: "cancelled", message: "chat closed"))) }
                guard pickerCurrent() else { delegate.finish(.failure(DGPluginError(code: "cancelled", message: "file selection is no longer current"))); return true }
                present(picker, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak delegate] in delegate?.finish(.failure(DGPluginError(code: "timeout", message: "file selection timed out"))) }
            case "files.read":
                guard Set(arguments.keys) == ["handle"], let handle = arguments["handle"]?.stringValue, let file = dgAdditionalPluginState.files[handle], file.scope == scope, file.expires >= ProcessInfo.processInfo.systemUptime else { throw DGPluginError(code: "stale_handle", message: "selected file handle expired") }
                completion(.success(.object(["text": .string(file.text), "encoding": .string("utf8")])))
            case "messages.prepare", "messages.compose", "messages.sendInteractive":
                try dgPluginMessageAction(installationId: installationId, scope: scope, method: method, arguments: arguments, pluginName: pluginName, validity: validity, completion: completion)
            case "messages.send", "messages.edit", "messages.delete":
                try dgPluginDirectMessageAction(installationId: installationId, scope: scope, method: method, arguments: arguments, validity: validity, completion: completion)
            case "translation.request":
                guard Set(arguments.keys).isSubset(of: ["targetLanguage", "text"]), let language = arguments["targetLanguage"]?.stringValue, language.range(of: "^[A-Za-z]{2,3}(-[A-Za-z]{2,8})?$", options: .regularExpression) != nil, let text = dgPluginSelectedText(installationId: installationId), !text.isEmpty, text.utf16.count <= 4096, arguments["text"] == nil || arguments["text"] == .string(text) else { throw DGPluginError(code: "scope_denied", message: "translation requires the exact native text selection") }
                dgPluginConfirm(installationId: installationId, scope: scope, title: pluginName, text: dgPluginText("Перевести через Telegram · ", "Translate with Telegram · ") + language + "\n\n" + text, validity: validity, completion: completion) { [weak self] finish, confirmationCurrent, resources in
                    guard let self, confirmationCurrent() else { finish(.failure(DGPluginError(code: "cancelled", message: "translation cancelled"))); return }
                    resources.add((self.context.engine.messages.translate(text: text, toLang: language) |> take(1) |> deliverOnMainQueue).start(next: { translated in
                        guard confirmationCurrent(), let translated else { finish(.failure(DGPluginError(code: "cancelled", message: "translation is unavailable or was cancelled"))); return }
                        finish(.success(.object(["text": .string(translated.0), "service": .string("telegram"), "targetLanguage": .string(language)])))
                    }, error: { _ in finish(.failure(DGPluginError(code: "service_error", message: "telegram translation failed"))) }))
                }
            case "notifications.local":
                guard Set(arguments.keys) == ["text"], let text = arguments["text"]?.stringValue, !text.isEmpty, text.utf16.count <= 512 else { throw DGPluginError(code: "invalid_argument", message: "invalid local notification text") }
                let center = UNUserNotificationCenter.current()
                let identifier = "donutgram.plugin." + UUID().uuidString.lowercased()
                let lifetime = dgPluginChatState.lifetime
                let chatCurrent = lifetime.snapshot()
                let notificationCurrent = { chatCurrent() && validity() }
                var token: UUID?
                token = manager.ownNativeResource(installationId: installationId, scope: scope, cleanup: { [weak lifetime] in
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                    if let token { lifetime?.release(token) }
                })
                guard let token else { throw DGPluginError(code: "quota_exceeded", message: "notification resource limit reached") }
                lifetime.own(token) {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                    manager.releaseNativeResource(installationId: installationId, token: token)
                }
                guard notificationCurrent() else {
                    lifetime.release(token)
                    manager.releaseNativeResource(installationId: installationId, token: token)
                    completion(.failure(DGPluginError(code: "cancelled", message: "notification context is no longer active")))
                    return true
                }
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        guard granted, notificationCurrent() else {
                            lifetime.release(token)
                            manager.releaseNativeResource(installationId: installationId, token: token)
                            completion(.failure(DGPluginError(code: "permission_denied", message: "local notifications are not authorized or chat closed")))
                            return
                        }
                        let content = UNMutableNotificationContent(); content.title = pluginName; content.body = text
                        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { error in
                            DispatchQueue.main.async {
                                let current = notificationCurrent()
                                if error != nil || !current {
                                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                                    lifetime.release(token)
                                    manager.releaseNativeResource(installationId: installationId, token: token)
                                }
                                completion(error == nil && current ? .success(.null) : .failure(DGPluginError(code: "cancelled", message: "notification was not scheduled")))
                            }
                        }
                    }
                }
            default: break
            }
        } catch let error as DGPluginError { completion(.failure(error)) }
        catch { completion(.failure(DGPluginError(code: "invalid_argument", message: "invalid native plugin action"))) }
        return true
    }

    private func dgPluginConfirm(installationId: String, scope: String, title: String, text: String, validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void, accepted: @escaping (@escaping (Result<DGPluginJSON, DGPluginError>) -> Void, @escaping () -> Bool, DisposableSet) -> Void) {
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        let state = DGPluginConfirmationState()
        let lifetime = dgPluginChatState.lifetime
        let chatCurrent = lifetime.snapshot()
        let resources = DisposableSet()
        var token: UUID?
        var alert: ViewController?
        let finish: (Result<DGPluginJSON, DGPluginError>) -> Void = { [weak lifetime] result in
            guard state.finish() else { return }
            resources.dispose()
            if let token {
                lifetime?.release(token)
                manager.releaseNativeResource(installationId: installationId, token: token)
            }
            alert?.dismiss(); alert = nil; completion(result)
        }
        let confirmationCurrent = { state.isCurrent() && chatCurrent() && validity() }
        let controller = textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: { finish(.failure(DGPluginError(code: "cancelled", message: "native action cancelled"))) }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
            guard state.accept(), confirmationCurrent() else { finish(.failure(DGPluginError(code: "cancelled", message: "native action is no longer current"))); return }
            accepted(finish, confirmationCurrent, resources)
        })], dismissOnOutsideTap: false)
        alert = controller
        token = manager.ownNativeResource(installationId: installationId, scope: scope) { finish(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))) }
        guard let token else { finish(.failure(DGPluginError(code: "quota_exceeded", message: "native action resource limit reached"))); return }
        lifetime.own(token) { finish(.failure(DGPluginError(code: "cancelled", message: "chat closed"))) }
        guard confirmationCurrent() else { finish(.failure(DGPluginError(code: "cancelled", message: "native confirmation is no longer current"))); return }
        present(controller, in: .window(.root))
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { finish(.failure(DGPluginError(code: "timeout", message: "native confirmation expired"))) }
    }

    private func dgPluginDirectMessageAction(installationId: String, scope: String, method: String, arguments: [String: DGPluginJSON], validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) throws {
        guard dgPluginSafeComposer(), let peerId = chatLocation.peerId else { throw DGPluginError(code: "scope_denied", message: "an active chat is required") }
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        let threadId = chatLocation.threadId
        let lifetime = dgPluginChatState.lifetime
        let chatCurrent = lifetime.snapshot()
        let sendCurrent = { chatCurrent() && validity() }
        let current = { [weak self] in
            guard let self else { return false }
            return sendCurrent() && self.dgPluginSafeComposer() && self.chatLocation.peerId == peerId && self.chatLocation.threadId == threadId
        }
        let text = arguments["text"]?.stringValue
        if method != "messages.delete" {
            guard let text, !text.isEmpty, text.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "expected ordinary message text") }
        }
        let messageId: EngineMessage.Id?
        if method == "messages.send" {
            guard Set(arguments.keys) == ["text"], presentationInterfaceState.sendPaidMessageStars == nil else { throw DGPluginError(code: "permission_denied", message: "only ordinary unpaid text can be sent") }
            messageId = nil
        } else {
            guard Set(arguments.keys).isSubset(of: method == "messages.edit" ? ["handle", "text"] : ["handle"]) else { throw DGPluginError(code: "invalid_argument", message: "unexpected message action parameter") }
            if let handleValue = arguments["handle"] {
                guard let handle = handleValue.stringValue, let snapshot = dgAdditionalPluginState.messages[handle],
                      snapshot.scope == scope, snapshot.message.id.peerId == peerId, snapshot.expires >= ProcessInfo.processInfo.systemUptime else { throw DGPluginError(code: "stale_handle", message: "selected message handle expired") }
                messageId = snapshot.message.id
                dgAdditionalPluginState.messages.removeValue(forKey: handle)
            } else {
                guard let selected = dgPluginChatState.selectedMessages[installationId], selected.id.peerId == peerId else { throw DGPluginError(code: "scope_denied", message: "select a message using its plugin menu action") }
                messageId = selected.id
            }
        }
        let disposable = DisposableSet()
        var token: UUID?
        var finished = false
        let finish: (Result<DGPluginJSON, DGPluginError>) -> Void = { [weak lifetime] result in
            guard !finished else { return }
            finished = true
            disposable.dispose()
            if let token {
                lifetime?.release(token)
                manager.releaseNativeResource(installationId: installationId, token: token)
            }
            completion(result)
        }
        token = manager.ownNativeResource(installationId: installationId, scope: scope, cleanup: {
            DispatchQueue.main.async { finish(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))) }
        })
        guard let token else { throw DGPluginError(code: "quota_exceeded", message: "native resource limit reached") }
        lifetime.own(token) { finish(.failure(DGPluginError(code: "cancelled", message: "chat closed"))) }
        guard sendCurrent() else { finish(.failure(DGPluginError(code: "cancelled", message: "message action is no longer current"))); return }
        if method == "messages.send", let text {
            disposable.add((context.engine.messages.enqueueConfirmedUnpaidPluginText(to: peerId, threadId: threadId, text: text, sendAsPeerId: presentationInterfaceState.currentSendAsPeerId, isCurrent: sendCurrent) |> take(1) |> deliverOnMainQueue).start(next: { queued in
                finish(queued ? .success(.object(["status": .string("queued")])) : .failure(DGPluginError(code: "send_failed", message: "message was not queued")))
            }))
        } else if let messageId {
            disposable.add((context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId)) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] message in
                guard let self, current(), let message else { finish(.failure(DGPluginError(code: "cancelled", message: "message or chat is no longer available"))); return }
                if method == "messages.edit", let text {
                    guard canEditMessage(context: self.context, limitsConfiguration: self.context.currentLimitsConfiguration.with { EngineConfiguration.Limits($0) }, message: message._asMessage()) else { finish(.failure(DGPluginError(code: "permission_denied", message: "telegram does not allow editing this message"))); return }
                    disposable.add((self.context.engine.messages.requestEditMessage(messageId: messageId, text: text, media: .keep, entities: nil, richText: nil, inlineStickers: [:]) |> deliverOnMainQueue).start(next: { result in
                        if case let .done(edited) = result { finish(edited ? .success(.object(["status": .string("edited")])) : .failure(DGPluginError(code: "edit_failed", message: "message could not be edited"))) }
                    }, error: { _ in finish(.failure(DGPluginError(code: "edit_failed", message: "telegram rejected the edit"))) }))
                } else {
                    disposable.add((self.context.sharedContext.chatAvailableMessageActions(engine: self.context.engine, accountPeerId: self.context.account.peerId, messageIds: [messageId], keepUpdated: false) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] actions in
                        guard let self, current(), !actions.disableDelete, actions.options.contains(.deleteGlobally) else { finish(.failure(DGPluginError(code: "permission_denied", message: "telegram does not allow deleting this message for everyone"))); return }
                        disposable.add((self.context.engine.messages.deleteMessagesInteractively(messageIds: [messageId], type: .forEveryone) |> deliverOnMainQueue).start(completed: {
                            finish(.success(.object(["status": .string("deletionRequested")])))
                        }))
                    }))
                }
            }))
        }
    }

    private func dgPluginMessageAction(installationId: String, scope: String, method: String, arguments: [String: DGPluginJSON], pluginName: String, validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) throws {
        guard dgPluginSafeComposer(), let peerId = chatLocation.peerId, let peer = presentationInterfaceState.renderedPeer?.chatMainPeer, presentationInterfaceState.sendPaidMessageStars == nil else { throw DGPluginError(code: "permission_denied", message: "plugins can only prepare ordinary unpaid messages in the selected chat") }
        let recipient = String(peerId.toInt64()) + ":" + String(chatLocation.threadId ?? 0)
        let title = String(peer.debugDisplayTitle.prefix(128))
        let store = dgAdditionalPluginState.actions
        if method == "messages.prepare" {
            guard Set(arguments.keys) == ["text"], let text = arguments["text"]?.stringValue else { throw DGPluginError(code: "invalid_argument", message: "expected ordinary message text") }
            let handle = try store.prepare(scope: scope, recipient: recipient, text: text)
            completion(.success(.object(["handle": .string(handle), "recipient": .string(title), "text": .string(text), "expiresIn": .number(45)]))); return
        }
        let handle: String
        if method == "messages.compose" {
            guard Set(arguments.keys) == ["text"], let text = arguments["text"]?.stringValue else { throw DGPluginError(code: "invalid_argument", message: "expected draft text") }
            handle = try store.prepare(scope: scope, recipient: recipient, text: text)
        } else {
            guard Set(arguments.keys) == ["handle"], let value = arguments["handle"]?.stringValue else { throw DGPluginError(code: "invalid_argument", message: "expected native preview handle") }
            handle = value
        }
        let text = try store.preview(handle: handle, scope: scope, recipient: recipient)
        let draft = presentationInterfaceState.interfaceState.effectiveInputState
        let threadId = chatLocation.threadId
        // The identity the user confirms is the one the message is sent with: captured now, not re-read later.
        let sendAsPeerId = presentationInterfaceState.currentSendAsPeerId
        let identity = sendAsPeerId.flatMap { id in id == context.account.peerId ? nil : presentationInterfaceState.sendAsPeers?.first(where: { $0.peer.id == id })?.peer.compactDisplayTitle }
        let action = method == "messages.compose" ? dgPluginText("Вставить в поле ввода", "Insert into the input field") : dgPluginText("Отправить сообщение", "Send message")
        let identityText = method == "messages.compose" ? "" : identity.map { dgPluginText(" · от имени ", " · as ") + String($0.prefix(128)) } ?? ""
        dgPluginConfirm(installationId: installationId, scope: scope, title: pluginName, text: action + " · " + title + identityText + "\n\n" + text, validity: validity, completion: completion) { [weak self] finish, confirmationCurrent, resources in
            guard let self, confirmationCurrent(), self.chatLocation.peerId == peerId, self.chatLocation.threadId == threadId, self.dgPluginSafeComposer(), self.presentationInterfaceState.sendPaidMessageStars == nil else { store.cancel(handle: handle); finish(.failure(DGPluginError(code: "cancelled", message: "recipient, price or account changed"))); return }
            resources.add((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars(id: peerId)) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] price in
                guard let self, confirmationCurrent(), price == nil, self.chatLocation.peerId == peerId, self.chatLocation.threadId == threadId, self.presentationInterfaceState.sendPaidMessageStars == nil else { store.cancel(handle: handle); finish(.failure(DGPluginError(code: "permission_denied", message: "paid or stale recipient is not allowed"))); return }
                do {
                    let approvedText = try store.consume(handle: handle, scope: scope, recipient: recipient, paidRecipient: price != nil)
                    if method == "messages.compose" {
                        guard self.presentationInterfaceState.interfaceState.effectiveInputState == draft, let interaction = self.interfaceInteraction else { throw DGPluginError(code: "conflict", message: "draft changed during native preview") }
                        var applied = false
                        interaction.updateTextInputStateAndMode { current, mode in
                            guard confirmationCurrent(), current == draft, self.presentationInterfaceState.interfaceState.editMessage == nil else { return (current, mode) }
                            let range = current.selectionRange
                            applied = true
                            return (current.replacingFlatRange(NSRange(location: range.lowerBound, length: range.count), with: approvedText), mode)
                        }
                        guard applied else { throw DGPluginError(code: "conflict", message: "draft was not changed because the native confirmation became stale") }
                        finish(.success(.object(["status": .string("draftPrepared")])))
                    } else {
                        resources.add((self.context.engine.messages.enqueueConfirmedUnpaidPluginText(to: peerId, threadId: threadId, text: approvedText, sendAsPeerId: sendAsPeerId, isCurrent: confirmationCurrent) |> take(1) |> deliverOnMainQueue).start(next: { queued in
                            finish(queued ? .success(.object(["status": .string("queued")])) : .failure(DGPluginError(code: "send_failed", message: "ordinary unpaid message was not queued")))
                        }))
                    }
                } catch let error as DGPluginError { finish(.failure(error)) }
                catch { finish(.failure(DGPluginError(code: "invalid_argument", message: "native confirmation failed"))) }
            }))
        }
    }
}
