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

private var dgAdditionalPluginStateKey: UInt8 = 0

private final class DGPluginAdditionalState {
    let actions = DGPluginNativeActionStore()
    var files: [String: (scope: String, text: String, expires: TimeInterval)] = [:]
    var picker: DGPluginTextPicker?
    var ownedScopes = Set<String>()
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
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 49153) ?? Data()
            guard data.count <= 49152, let text = String(data: data, encoding: .utf8), validity() else { throw DGPluginError(code: "invalid_argument", message: "selected file must be bounded utf8 text") }
            finish(.success((String(url.lastPathComponent.prefix(128)), text)))
        } catch let error as DGPluginError { finish(.failure(error)) }
        catch { finish(.failure(DGPluginError(code: "invalid_argument", message: "unable to read selected text file"))) }
    }
}

extension ChatControllerImpl {
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
        let supported: Set<String> = ["messages.read", "chats.metadata", "peers.read", "navigation.open", "notifications.local", "files.pick", "files.read", "messages.prepare", "messages.sendInteractive", "messages.compose", "translation.request"]
        guard supported.contains(method) else { return false }
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        guard let scope = manager.nativeScope(installationId: installationId), validity(), isNodeLoaded, view.window != nil else { completion(.failure(DGPluginError(code: "cancelled", message: "native context is no longer active"))); return true }
        let arguments = params.objectValue ?? [:]
        let pluginName = manager.installations.first(where: { $0.id == installationId })?.manifest.name ?? "plugin"
        if !dgAdditionalPluginState.ownedScopes.contains(scope) {
            guard manager.ownNativeResource(installationId: installationId, scope: scope, cleanup: { [weak self] in
                guard let self else { return }
                self.dgAdditionalPluginState.actions.removeAll(scope: scope)
                self.dgAdditionalPluginState.files = self.dgAdditionalPluginState.files.filter { $0.value.scope != scope }
                self.dgAdditionalPluginState.ownedScopes.remove(scope)
            }) != nil else { completion(.failure(DGPluginError(code: "quota_exceeded", message: "native scope resource limit reached"))); return true }
            dgAdditionalPluginState.ownedScopes.insert(scope)
        }
        do {
            switch method {
            case "messages.read":
                guard arguments.isEmpty, let message = dgPluginChatState.selectedMessages[installationId], dgPluginSafeMessage(message) else { throw DGPluginError(code: "scope_denied", message: "choose one eligible message using its native plugin action") }
                completion(.success(.array([.object(["handle": .string(UUID().uuidString.lowercased()), "text": .string(message.text), "timestamp": .number(Double(message.timestamp)), "entities": .array([]), "entitiesComplete": .bool(false), "mediaComplete": .bool(false)])])))
            case "chats.metadata":
                guard arguments.isEmpty, dgPluginSafeComposer(), let peer = presentationInterfaceState.renderedPeer?.chatMainPeer else { throw DGPluginError(code: "scope_denied", message: "no eligible selected chat") }
                completion(.success(.object(["handle": .string(UUID().uuidString.lowercased()), "title": .string(String(peer.debugDisplayTitle.prefix(128))), "scope": .string("currentNativeChat") ])))
            case "peers.read":
                guard arguments.isEmpty, let message = dgPluginChatState.selectedMessages[installationId], dgPluginSafeMessage(message), let author = message.author, !author.isService else { throw DGPluginError(code: "scope_denied", message: "no eligible author selected by a native message action") }
                completion(.success(.array([.object(["handle": .string(UUID().uuidString.lowercased()), "title": .string(String(author.debugDisplayTitle.prefix(128)))])])))
            case "navigation.open":
                guard Set(arguments.keys) == ["screen"], arguments["screen"] == .string("plugins"), validity() else { throw DGPluginError(code: "scope_denied", message: "only the native plugin-management route is supported") }
                navigationController?.pushViewController(dgPluginsController(context: context))
                completion(.success(.null))
            case "files.pick":
                guard arguments.isEmpty, dgAdditionalPluginState.picker == nil else { throw DGPluginError(code: "conflict", message: "a text-file chooser is already open") }
                var token: UUID?
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .json], asCopy: true)
                let delegate = DGPluginTextPicker(validity: validity) { [weak self] result in
                    if let token { manager.releaseNativeResource(installationId: installationId, token: token) }
                    guard let self else { completion(.failure(DGPluginError(code: "cancelled", message: "chat closed"))); return }
                    self.dgAdditionalPluginState.picker = nil
                    switch result {
                    case let .failure(error): completion(.failure(error))
                    case let .success((name, text)):
                        guard validity() else { completion(.failure(DGPluginError(code: "cancelled", message: "file permission revoked"))); return }
                        self.dgAdditionalPluginState.files = self.dgAdditionalPluginState.files.filter { $0.value.expires >= ProcessInfo.processInfo.systemUptime }
                        guard self.dgAdditionalPluginState.files.count < 4 else { completion(.failure(DGPluginError(code: "quota_exceeded", message: "too many selected file handles"))); return }
                        let handle = UUID().uuidString.lowercased()
                        self.dgAdditionalPluginState.files[handle] = (scope, text, ProcessInfo.processInfo.systemUptime + 60)
                        completion(.success(.object(["handle": .string(handle), "name": .string(name), "size": .number(Double(text.utf8.count))])))
                    }
                }
                picker.delegate = delegate; picker.allowsMultipleSelection = false; delegate.controller = picker
                token = manager.ownNativeResource(installationId: installationId, scope: scope) { [weak delegate] in delegate?.finish(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))) }
                guard token != nil else { throw DGPluginError(code: "quota_exceeded", message: "native resource limit reached") }
                dgAdditionalPluginState.picker = delegate
                present(picker, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak delegate] in delegate?.finish(.failure(DGPluginError(code: "timeout", message: "file selection timed out"))) }
            case "files.read":
                guard Set(arguments.keys) == ["handle"], let handle = arguments["handle"]?.stringValue, let file = dgAdditionalPluginState.files[handle], file.scope == scope, file.expires >= ProcessInfo.processInfo.systemUptime else { throw DGPluginError(code: "stale_handle", message: "selected file handle expired") }
                completion(.success(.object(["text": .string(file.text), "encoding": .string("utf8")])))
            case "messages.prepare", "messages.compose", "messages.sendInteractive":
                try dgPluginMessageAction(installationId: installationId, scope: scope, method: method, arguments: arguments, pluginName: pluginName, validity: validity, completion: completion)
            case "translation.request":
                guard Set(arguments.keys).isSubset(of: ["targetLanguage", "text"]), let language = arguments["targetLanguage"]?.stringValue, language.range(of: "^[A-Za-z]{2,3}(-[A-Za-z]{2,8})?$", options: .regularExpression) != nil, let text = dgPluginSelectedText(installationId: installationId), !text.isEmpty, text.utf16.count <= 4096, arguments["text"] == nil || arguments["text"] == .string(text) else { throw DGPluginError(code: "scope_denied", message: "translation requires the exact native text selection") }
                dgPluginConfirm(installationId: installationId, scope: scope, title: pluginName, text: "telegram translation · " + language + "\n\n" + text, validity: validity, completion: completion) { [weak self] finish in
                    guard let self, validity() else { finish(.failure(DGPluginError(code: "cancelled", message: "translation cancelled"))); return }
                    let disposable = (self.context.engine.messages.translate(text: text, toLang: language) |> take(1) |> deliverOnMainQueue).start(next: { translated in
                        guard validity(), let translated else { finish(.failure(DGPluginError(code: "cancelled", message: "translation is unavailable or was cancelled"))); return }
                        finish(.success(.object(["text": .string(translated.0), "service": .string("telegram"), "targetLanguage": .string(language)])))
                    }, error: { _ in finish(.failure(DGPluginError(code: "service_error", message: "telegram translation failed"))) })
                    _ = manager.ownNativeResource(installationId: installationId, scope: scope) { disposable.dispose() }
                }
            case "notifications.local":
                guard Set(arguments.keys) == ["text"], let text = arguments["text"]?.stringValue, !text.isEmpty, text.utf16.count <= 512 else { throw DGPluginError(code: "invalid_argument", message: "invalid local notification text") }
                let center = UNUserNotificationCenter.current()
                let identifier = "donutgram.plugin." + UUID().uuidString.lowercased()
                guard manager.ownNativeResource(installationId: installationId, scope: scope, cleanup: { center.removePendingNotificationRequests(withIdentifiers: [identifier]); center.removeDeliveredNotifications(withIdentifiers: [identifier]) }) != nil else { throw DGPluginError(code: "quota_exceeded", message: "notification resource limit reached") }
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        guard granted, validity() else { completion(.failure(DGPluginError(code: "permission_denied", message: "local notifications are not authorized"))); return }
                        let content = UNMutableNotificationContent(); content.title = pluginName; content.body = text
                        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { error in
                            DispatchQueue.main.async { completion(error == nil && validity() ? .success(.null) : .failure(DGPluginError(code: "cancelled", message: "notification was not scheduled"))) }
                        }
                    }
                }
            default: break
            }
        } catch let error as DGPluginError { completion(.failure(error)) }
        catch { completion(.failure(DGPluginError(code: "invalid_argument", message: "invalid native plugin action"))) }
        return true
    }

    private func dgPluginConfirm(installationId: String, scope: String, title: String, text: String, validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void, accepted: @escaping (@escaping (Result<DGPluginJSON, DGPluginError>) -> Void) -> Void) {
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        var completed = false
        var token: UUID?
        var alert: ViewController?
        let finish: (Result<DGPluginJSON, DGPluginError>) -> Void = { result in
            guard !completed else { return }; completed = true
            if let token { manager.releaseNativeResource(installationId: installationId, token: token) }
            alert?.dismiss(); alert = nil; completion(result)
        }
        let controller = textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: { finish(.failure(DGPluginError(code: "cancelled", message: "native action cancelled"))) }), TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
            guard validity() else { finish(.failure(DGPluginError(code: "cancelled", message: "native action is no longer current"))); return }
            accepted(finish)
        })])
        alert = controller
        token = manager.ownNativeResource(installationId: installationId, scope: scope) { finish(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))) }
        guard token != nil else { finish(.failure(DGPluginError(code: "quota_exceeded", message: "native action resource limit reached"))); return }
        present(controller, in: .window(.root))
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { finish(.failure(DGPluginError(code: "timeout", message: "native confirmation expired"))) }
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
        let action = method == "messages.compose" ? "prepare draft" : "send ordinary message"
        dgPluginConfirm(installationId: installationId, scope: scope, title: pluginName, text: action + " · " + title + "\n\n" + text, validity: validity, completion: completion) { [weak self] finish in
            guard let self, validity(), self.chatLocation.peerId == peerId, self.chatLocation.threadId == threadId, self.dgPluginSafeComposer(), self.presentationInterfaceState.sendPaidMessageStars == nil else { store.cancel(handle: handle); finish(.failure(DGPluginError(code: "cancelled", message: "recipient, price or account changed"))); return }
            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars(id: peerId)) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] price in
                guard let self, validity(), price == nil, self.chatLocation.peerId == peerId, self.chatLocation.threadId == threadId, self.presentationInterfaceState.sendPaidMessageStars == nil else { store.cancel(handle: handle); finish(.failure(DGPluginError(code: "permission_denied", message: "paid or stale recipient is not allowed"))); return }
                do {
                    let approvedText = try store.consume(handle: handle, scope: scope, recipient: recipient, paidRecipient: price != nil)
                    if method == "messages.compose" {
                        guard self.presentationInterfaceState.interfaceState.effectiveInputState == draft, let interaction = self.interfaceInteraction else { throw DGPluginError(code: "conflict", message: "draft changed during native preview") }
                        interaction.updateTextInputStateAndMode { current, mode in
                            guard validity(), current == draft else { return (current, mode) }
                            let range = current.selectionRange
                            return (current.replacingFlatRange(NSRange(location: range.lowerBound, length: range.count), with: approvedText), mode)
                        }
                        finish(.success(.object(["status": .string("draftPrepared")])))
                    } else {
                        let _ = (self.context.engine.messages.enqueueConfirmedUnpaidPluginText(to: peerId, threadId: threadId, text: approvedText, isCurrent: validity) |> take(1) |> deliverOnMainQueue).start(next: { queued in
                            finish(queued ? .success(.object(["status": .string("queued")])) : .failure(DGPluginError(code: "send_failed", message: "ordinary unpaid message was not queued")))
                        })
                    }
                } catch let error as DGPluginError { finish(.failure(error)) }
                catch { finish(.failure(DGPluginError(code: "invalid_argument", message: "native confirmation failed"))) }
            })
        }
    }
}
