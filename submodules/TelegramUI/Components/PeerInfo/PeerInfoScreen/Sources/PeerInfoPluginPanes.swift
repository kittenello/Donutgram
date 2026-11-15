import Foundation
import AccountContext
import TelegramCore
import DGPluginModel
import DGPluginHost
import PeerInfoPaneNode

extension PeerInfoScreenData {
    func applyPluginProfilePanes(context: AccountContext, isSettings: Bool, update: @escaping () -> Void) {
        let native = Set(self.nativeAvailablePanes)
        let manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        guard !isSettings, self.peer?.isService != true, self.chatPeer?.id.namespace != Namespaces.Peer.SecretChat, !native.isEmpty,
              manager.viewTransformState(slot: "profile").active else { self.applyPluginAvailablePanes(native); return }
        let items = self.nativeAvailablePanes.map { pane in
            DGPluginJSON.object(["id": .string(String(describing: pane)), "empty": .bool(self.pluginKnownEmptyPanes.contains(pane))])
        }
        let output = manager.transformedViewModel(slot: "profile", input: .object(["panes": .array(items)]), update: update)
        guard case let .array(panes)? = output.objectValue?["panes"] else { self.applyPluginAvailablePanes(native); return }
        let ids = Set(panes.compactMap { $0.objectValue?["id"]?.stringValue })
        self.applyPluginAvailablePanes(Set(self.nativeAvailablePanes.filter { ids.contains(String(describing: $0)) }))
    }
}
