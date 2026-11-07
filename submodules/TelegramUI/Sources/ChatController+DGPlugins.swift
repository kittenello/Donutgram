import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import ContextUI
import PresentationDataUtils
import DGPluginModel
import DGPluginHost
import DGPluginsUI

struct DGPluginDraftSnapshot {
    let owner: String
    let revision: String
    let state: ChatTextInputState
    let expires: TimeInterval
}

final class DGPluginChatState {
    var drafts: [String: DGPluginDraftSnapshot] = [:]
    var selectedMessages: [String: EngineMessage] = [:]
}

extension ChatControllerImpl {
    func dgBindChatPlugins() {
        dgBindPluginAccount(context: self.context)
        let manager = DGPluginManager.shared(accountKey: String(self.context.account.id.int64))
        manager.updateEnvironment(locale: self.presentationData.strings.primaryComponent.languageCode, appearance: self.presentationData.theme.overallDarkAppearance ? "dark" : "light")
        manager.nativeRequest = { [weak self] installationId, method, params, validity, completion in
            guard let self else { completion(.failure(DGPluginError(code: "cancelled", message: "chat is no longer available"))); return }
            self.dgHandlePluginRequest(installationId: installationId, method: method, params: params, validity: validity, completion: completion)
        }
        manager.nativeRender = { [weak self] page, pluginName, validity, callback in
            guard let self, self.isNodeLoaded, self.view.window != nil, validity() else { return .failure(DGPluginError(code: "cancelled", message: "chat is not visible")) }
            do {
                let controller = try dgPluginRenderedController(context: self.context, page: page, pluginName: pluginName, validity: validity, onCallback: callback)
                guard validity() else { return .failure(DGPluginError(code: "cancelled", message: "plugin page cancelled")) }
                self.present(controller, in: .window(.root))
                return .success({ [weak controller] in controller?.dismiss() })
            } catch let error as DGPluginError { return .failure(error) }
            catch { return .failure(DGPluginError(code: "invalid_argument", message: "invalid plugin page")) }
        }
    }

    private func dgPluginSafeComposer() -> Bool {
        guard self.isNodeLoaded, self.view.window != nil, self.presentationInterfaceState.interfaceState.editMessage == nil,
              let peer = self.presentationInterfaceState.renderedPeer?.chatMainPeer, !EnginePeer(peer).isService else { return false }
        return true
    }

    private func dgPluginSafeMessage(_ message: EngineMessage) -> Bool {
        guard !self.presentationInterfaceState.copyProtectionEnabled, !self.presentationInterfaceState.myCopyProtectionEnabled,
              message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              !message._asMessage().isCopyProtectedIgnoringDonutgramSetting(), message.text.utf16.count <= 16384,
              message.author?.isService != true, let peer = message.peers[message.id.peerId], !EnginePeer(peer).isService,
              !message.media.contains(where: { $0 is TelegramMediaAction }) else { return false }
        return true
    }

    private func dgHandlePluginRequest(installationId: String, method: String, params: DGPluginJSON, validity: @escaping () -> Bool, completion: @escaping (Result<DGPluginJSON, DGPluginError>) -> Void) {
        guard Thread.isMainThread, self.isNodeLoaded, self.view.window != nil, validity() else { completion(.failure(DGPluginError(code: "cancelled", message: "native context is no longer active"))); return }
        let arguments = params.objectValue ?? [:]
        do {
            switch method {
            case "composer.getActiveDraft":
                guard self.dgPluginSafeComposer() else { throw DGPluginError(code: "scope_denied", message: "this composer is unavailable to plugins") }
                let state = self.presentationInterfaceState.interfaceState.effectiveInputState
                let text = state.content.plainText
                guard text.utf16.count <= 16384 else { throw DGPluginError(code: "quota_exceeded", message: "draft exceeds the plugin snapshot limit") }
                let now = ProcessInfo.processInfo.systemUptime
                self.dgPluginChatState.drafts = self.dgPluginChatState.drafts.filter { $0.value.expires > now && $0.value.owner != installationId }
                guard self.dgPluginChatState.drafts.count < 16 else { throw DGPluginError(code: "quota_exceeded", message: "too many draft snapshots") }
                let handle = UUID().uuidString.lowercased()
                let revision = UUID().uuidString.lowercased()
                self.dgPluginChatState.drafts[handle] = DGPluginDraftSnapshot(owner: installationId, revision: revision, state: state, expires: now + 30)
                completion(.success(.object(["handle": .string(handle), "revision": .string(revision), "text": .string(text), "selection": .object(["start": .number(Double(state.selectionRange.lowerBound)), "end": .number(Double(state.selectionRange.upperBound))]), "entities": .array([]), "entitiesComplete": .bool(false), "plainTextComplete": .bool(false)])))
            case "composer.replaceSelection":
                guard Set(arguments.keys).isSubset(of: ["composer", "handle", "expectedRevision", "text", "range"]), self.dgPluginSafeComposer(), let handle = arguments["composer"]?.stringValue ?? arguments["handle"]?.stringValue,
                      (arguments["composer"] == nil || arguments["handle"] == nil || arguments["composer"] == arguments["handle"]),
                      let revision = arguments["expectedRevision"]?.stringValue, let text = arguments["text"]?.stringValue, text.utf16.count <= 4096,
                      let snapshot = self.dgPluginChatState.drafts[handle], snapshot.owner == installationId, snapshot.revision == revision,
                      snapshot.expires >= ProcessInfo.processInfo.systemUptime else { throw DGPluginError(code: "stale_handle", message: "draft handle expired or does not match this plugin") }
                self.dgPluginChatState.drafts.removeValue(forKey: handle)
                let originalText = snapshot.state.content.plainText as NSString
                var range = NSRange(location: snapshot.state.selectionRange.lowerBound, length: snapshot.state.selectionRange.count)
                if let requested = arguments["range"] {
                    guard let object = requested.objectValue, Set(object.keys) == ["start", "end"], case let .number(start)? = object["start"], case let .number(end)? = object["end"], start.isFinite, end.isFinite, start.rounded() == start, end.rounded() == end, start >= 0, end >= start, end <= Double(originalText.length) else { throw DGPluginError(code: "invalid_argument", message: "invalid draft range") }
                    range = NSRange(location: Int(start), length: Int(end - start))
                }
                guard range.location >= 0, range.length >= 0, range.location <= originalText.length, range.length <= originalText.length - range.location,
                      self.dgPluginUTF16Boundary(originalText, range.location), self.dgPluginUTF16Boundary(originalText, range.location + range.length),
                      let interaction = self.interfaceInteraction else { throw DGPluginError(code: "invalid_argument", message: "draft range crosses an invalid text boundary") }
                guard validity(), self.presentationInterfaceState.interfaceState.effectiveInputState == snapshot.state else { throw DGPluginError(code: "revision_conflict", message: "draft changed after the snapshot") }
                var applied = false
                interaction.updateTextInputStateAndMode { current, mode in
                    guard validity(), current == snapshot.state, self.presentationInterfaceState.interfaceState.editMessage == nil else { return (current, mode) }
                    applied = true
                    return (current.replacingFlatRange(range, with: text), mode)
                }
                guard applied else { throw DGPluginError(code: "revision_conflict", message: "draft changed before the edit was applied") }
                completion(.success(.null))
            case "selection.get":
                let text: String
                let source: String
                if let message = self.dgPluginChatState.selectedMessages[installationId] {
                    guard self.dgPluginSafeMessage(message) else { throw DGPluginError(code: "scope_denied", message: "this message cannot be shared with plugins") }
                    text = message.text
                    source = "message"
                } else {
                    guard self.dgPluginSafeComposer() else { throw DGPluginError(code: "scope_denied", message: "no eligible text selection") }
                    let state = self.presentationInterfaceState.interfaceState.effectiveInputState
                    let input = state.content.plainText as NSString
                    let selected = state.selectionRange
                    guard selected.lowerBound >= 0, selected.upperBound <= input.length, !selected.isEmpty else { throw DGPluginError(code: "scope_denied", message: "select text before running this command") }
                    text = input.substring(with: NSRange(location: selected.lowerBound, length: selected.count))
                    source = "composer"
                }
                guard text.utf16.count <= 16384, validity() else { throw DGPluginError(code: "quota_exceeded", message: "selection exceeds the plugin limit") }
                completion(.success(.object(["text": .string(text), "source": .string(source), "entities": .array([]), "entitiesComplete": .bool(false)])))
            case "ui.toast":
                guard Set(arguments.keys) == ["text"], let text = arguments["text"]?.stringValue, !text.isEmpty, text.utf16.count <= 512, validity() else { throw DGPluginError(code: "invalid_argument", message: "invalid plugin notice") }
                self.present(textAlertController(context: self.context, title: "plugin", text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                completion(.success(.null))
            default:
                throw DGPluginError(code: "feature_unavailable", message: "this native adapter is unavailable")
            }
        } catch let error as DGPluginError { completion(.failure(error)) }
        catch { completion(.failure(DGPluginError(code: "invalid_argument", message: "invalid native request"))) }
    }

    private func dgPluginUTF16Boundary(_ text: NSString, _ index: Int) -> Bool {
        guard index > 0, index < text.length else { return index >= 0 && index <= text.length }
        return !(0xd800 ... 0xdbff).contains(text.character(at: index - 1)) || !(0xdc00 ... 0xdfff).contains(text.character(at: index))
    }

    func dgPluginMenuItems(placements: Set<String>, message: EngineMessage? = nil) -> [ContextMenuItem] {
        guard self.dgPluginSafeComposer(), message.map(self.dgPluginSafeMessage) ?? true else { return [] }
        let manager = DGPluginManager.shared(accountKey: String(self.context.account.id.int64))
        return manager.commands.filter { placements.contains($0.placement) }.prefix(32).map { command in
            .action(ContextMenuActionItem(text: command.title, icon: { _ in nil }, action: { [weak self] _, dismiss in
                dismiss(.default)
                guard let self else { return }
                self.dgBindChatPlugins()
                if let message { self.dgPluginChatState.selectedMessages[command.installationId] = message }
                else { self.dgPluginChatState.selectedMessages.removeValue(forKey: command.installationId) }
                manager.runCommand(installationId: command.installationId, commandId: command.id, input: .null) { [weak self] result in
                    guard let self else { return }
                    self.dgPluginChatState.selectedMessages.removeValue(forKey: command.installationId)
                    self.dgPluginChatState.drafts = self.dgPluginChatState.drafts.filter { $0.value.owner != command.installationId }
                    if case let .failure(error) = result {
                        self.present(textAlertController(context: self.context, title: "plugin", text: error.code + ": " + error.message, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    }
                }
            }))
        }
    }
}
