import Foundation
import DGSimpleSettings

// Minimal peer fixtures; the getters and badge lookup below come from production sources.
public struct PeerId: Codable, Equatable {
    public struct Id: Codable, Equatable {
        public let value: Int64
        public func _internalGetInt64Value() -> Int64 { return self.value }
    }
    public let namespace: Int32
    public let id: Id
}
public enum Namespaces {
    public enum Peer { public static let CloudUser: Int32 = 0 }
}
public struct MessageTextEntity: Codable, Equatable { public let offset: Int }
public struct PeerFlags: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isVerified = PeerFlags(rawValue: 1)
}
public protocol Peer {}
public final class TelegramUser: Peer {
    public let flags: PeerFlags
    public let verificationIconFileId: Int64?
    public init(verified: Bool, icon: Int64?) {
        self.flags = verified ? [.isVerified] : []
        self.verificationIconFileId = icon
    }
}
public final class TelegramChannel: Peer {
    public let flags: PeerFlags
    public let verificationIconFileId: Int64?
    public init(verified: Bool, icon: Int64?) {
        self.flags = verified ? [.isVerified] : []
        self.verificationIconFileId = icon
    }
}
public struct TelegramGroup: Peer {}
public struct EnginePeer {
    public typealias Id = PeerId
    private let peer: Peer
    public init(_ peer: Peer) { self.peer = peer }
    public func _asPeer() -> Peer { return self.peer }
}

// PRODUCTION

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
func userId(_ value: Int64, namespace: Int32 = 0) -> PeerId {
    return PeerId(namespace: namespace, id: PeerId.Id(value: value))
}

let key = "donutgram.appearance.hideVerification"
let settings = DGSimpleSettings.shared
switch CommandLine.arguments.dropFirst().first {
case "write-setting":
    settings.hideVerification = true
    UserDefaults.standard.synchronize()
    expect(settings.hideVerification, "enabled setting saved")
case "read-setting":
    expect(settings.hideVerification, "setting survives a fresh process")
    expect(!DonutgramVerificationDisplay.isVerified(true), "filter restored from disk")
    settings.hideVerification = false
    UserDefaults.standard.synchronize()
case "read-restored":
    expect(!settings.hideVerification, "disabled setting survives a fresh process")
    expect(DonutgramVerificationDisplay.isVerified(true), "verification restored after restart")
    UserDefaults.standard.removeObject(forKey: key)
default:
    let previous = UserDefaults.standard.object(forKey: key)
    defer {
        if let previous { UserDefaults.standard.set(previous, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
    UserDefaults.standard.removeObject(forKey: key)
    expect(!settings.hideVerification, "feature defaults to off")
    let description = PeerVerification(botId: userId(100), iconFileId: 999, description: "Verified by Hold", descriptionEntities: [MessageTextEntity(offset: 2)])
    let peers: [Peer] = [
        TelegramUser(verified: true, icon: nil),       // Telegram user / bot
        TelegramUser(verified: false, icon: 123),      // Hold
        TelegramUser(verified: true, icon: 456),       // ordinary and third-party together
        TelegramChannel(verified: true, icon: 789),    // channel / supergroup
        TelegramChannel(verified: false, icon: 987),   // Major
        TelegramGroup(),
    ]
    var notifications = 0
    let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: nil, queue: nil) { _ in notifications += 1 }
    defer { NotificationCenter.default.removeObserver(observer) }
    for hidden in [false, true, false] {
        settings.hideVerification = hidden
        expect(DonutgramVerificationDisplay.isHidden == hidden, "policy follows current setting")
        expect(DonutgramVerificationDisplay.verification(description) == (hidden ? nil : description), "organization text, icon and entities filtered together")
        expect(DonutgramVerificationDisplay.verification(nil) == nil, "no verification stays absent")
        for peer in peers {
            let rawVerified = peer.isVerified
            let rawIcon = peer.verificationIconFileId
            let engine = EnginePeer(peer)
            expect(peer.donutgramDisplayIsVerified == (rawVerified && !hidden), "raw peer badge visibility")
            expect(peer.donutgramDisplayVerificationIconFileId == (hidden ? nil : rawIcon), "raw peer custom icon visibility")
            expect(engine.donutgramDisplayIsVerified == (rawVerified && !hidden), "engine peer badge visibility")
            expect(engine.donutgramDisplayVerificationIconFileId == (hidden ? nil : rawIcon), "engine peer custom icon visibility")
            expect(engine.isVerified == rawVerified, "trust flag remains available when hidden")
            expect(engine.verificationIconFileId == rawIcon, "server icon is preserved")
        }
        expect(donutgramBadge(peerId: userId(7395289125)) == .baha, "Baha badge preserved")
        expect(donutgramBadge(peerId: userId(8997685381)) == .developer, "developer badge preserved")
        expect(donutgramBadge(peerId: userId(625977431)) == .developer, "second developer badge preserved")
        expect(donutgramBadge(peerId: userId(8494126379)) == .supporter, "supporter badge preserved")
        expect(donutgramBadge(peerId: userId(7395289125, namespace: 2)) == nil, "badge applies only to users")
        expect(donutgramBadge(peerId: userId(1)) == nil, "ordinary peers have no team badge")
    }
    expect(notifications == 3, "each actual setting change notifies observers")
    settings.hideVerification = false
    expect(notifications == 3, "unchanged value does not notify again")
}
print("Passed \(checks) verification visibility, preservation and settings checks.")
