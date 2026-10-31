enum NoError: Error {}

struct Signal<Value, Failure> {
    let values: [Value]
    static func single(_ value: Value) -> Self { return Self(values: [value]) }
}

infix operator |> : AdditionPrecedence
func |> <Input, Output>(value: Input, transform: (Input) -> Output) -> Output { return transform(value) }

func filter<Value, Failure>(_ predicate: @escaping (Value) -> Bool) -> (Signal<Value, Failure>) -> Signal<Value, Failure> {
    return { Signal(values: $0.values.filter(predicate)) }
}

func take<Value, Failure>(_ count: Int) -> (Signal<Value, Failure>) -> Signal<Value, Failure> {
    return { Signal(values: Array($0.values.prefix(count))) }
}

func map<Input, Output, Failure>(_ transform: @escaping (Input) -> Output) -> (Signal<Input, Failure>) -> Signal<Output, Failure> {
    return { Signal(values: $0.values.map(transform)) }
}

func mapToSignal<Input, Output, Failure>(_ transform: @escaping (Input) -> Signal<Output, Failure>) -> (Signal<Input, Failure>) -> Signal<Output, Failure> {
    return { Signal(values: $0.values.flatMap { transform($0).values }) }
}

struct RawId: Hashable {
    let value: Int64
    func _internalGetInt64Value() -> Int64 { return self.value }
}

struct PeerId: Hashable {
    let id: RawId
    init(_ value: Int64) { self.id = RawId(value: value) }
}

struct EnginePeer {
    typealias Id = PeerId
    let id: Id
    init(_ value: Int64) { self.id = PeerId(value) }
}

protocol EngineCachedPeerData {}

struct PeerVerification {
    let botId: PeerId
    let iconFileId: Int64
    let description: String
}

struct VerifierSettings {
    let iconFileId: Int64
    let customDescription: String?
    let companyName: String
}

struct BotInfo { let verifierSettings: VerifierSettings? }

struct CachedUserData: EngineCachedPeerData {
    let botInfo: BotInfo?
    let verification: PeerVerification?
    init(botInfo: BotInfo? = nil, verification: PeerVerification? = nil) {
        self.botInfo = botInfo
        self.verification = verification
    }
}

struct CachedChannelData: EngineCachedPeerData { let verification: PeerVerification? }

enum ResolvePeerResult {
    case progress
    case result(EnginePeer?)
}

final class Fixtures {
    var names: [String: EnginePeer] = [:]
    var ids: [Int64: EnginePeer] = [:]
    var cache: [PeerId: EngineCachedPeerData] = [:]
    var requestedNames: [String] = []
}

final class TelegramEngine {
    enum EngineData {
        enum Item {
            enum Peer {
                struct CachedData { let id: PeerId }
            }
        }
    }

    struct Peers {
        let fixtures: Fixtures
        func resolvePeerByName(name: String, referrer: String?) -> Signal<ResolvePeerResult, NoError> {
            self.fixtures.requestedNames.append(name)
            return Signal(values: [.progress, .result(self.fixtures.names[name])])
        }
        func findUserById(userId: Int64) -> Signal<EnginePeer?, NoError> {
            return .single(self.fixtures.ids[userId])
        }
        func fetchAndUpdateCachedPeerData(peerId: PeerId) -> Signal<Bool, NoError> { return .single(true) }
    }

    struct Data {
        let fixtures: Fixtures
        func get(_ item: EngineData.Item.Peer.CachedData) -> Signal<EngineCachedPeerData?, NoError> {
            return .single(self.fixtures.cache[item.id])
        }
    }

    let peers: Peers
    let data: Data
    init(_ fixtures: Fixtures) {
        self.peers = Peers(fixtures: fixtures)
        self.data = Data(fixtures: fixtures)
    }
}

struct AccountContext { let engine: TelegramEngine }

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

for (selection, userId, botName, sourceName) in [(DGLocalVerification.major, Int64(5489891396), "major", "imstoyak"), (.hold, 1272367206, "hold", "fuhao"), (.crow, 7308887716, "", "crow")] {
    let fixtures = Fixtures()
    let bot = EnginePeer(8365813836)
    let source = EnginePeer(userId)
    if !botName.isEmpty { fixtures.names[botName] = bot }
    fixtures.names[sourceName] = source
    fixtures.cache[source.id] = CachedUserData(verification: PeerVerification(botId: bot.id, iconFileId: 987654321, description: "server description"))
    let context = AccountContext(engine: TelegramEngine(fixtures))
    let loaded = donutgramLoadLocalVerification(context: context, verification: selection).values
    check(loaded.count == 1 && loaded[0]?.iconFileId == 987654321, "a real profile supplies the icon when bot settings are unavailable")
    check(loaded[0]?.description == "server description" && loaded[0]?.botId == 8365813836, "the profile supplies the description and verifier identity")
    fixtures.names[sourceName] = EnginePeer(userId + 1)
    check(donutgramLoadLocalVerification(context: context, verification: selection).values[0] == nil, "a transferred username cannot supply another account's verification")
    fixtures.ids[userId] = source
    fixtures.names.removeValue(forKey: sourceName)
    check(donutgramLoadLocalVerification(context: context, verification: selection).values[0]?.iconFileId == 987654321, "known user ids keep working after a username change")
    fixtures.cache[source.id] = CachedUserData(verification: PeerVerification(botId: PeerId(42), iconFileId: 12, description: "different verifier"))
    check(donutgramLoadLocalVerification(context: context, verification: selection, expectedBotId: 8365813836).values[0] == nil, "another verifier's badge cannot replace the saved organization")
}

let fixtures = Fixtures()
let majorBot = EnginePeer(500)
fixtures.names["major"] = majorBot
let context = AccountContext(engine: TelegramEngine(fixtures))
let requested = fixtures.requestedNames.count
check(donutgramLoadLocalVerification(context: context, verification: .none).values[0] == nil && fixtures.requestedNames.count == requested, "disabled verification does not fetch profiles")
fixtures.cache[majorBot.id] = CachedUserData(botInfo: BotInfo(verifierSettings: VerifierSettings(iconFileId: 503, customDescription: "bot description", companyName: "Major")))
check(donutgramLoadLocalVerification(context: context, verification: .major).values[0]?.iconFileId == 503, "available verifier settings remain a fallback")
print("local verification source and username change checks passed")
