struct Item: Equatable {
    enum Content: Equatable { case proxy, psa }
    struct Promo: Equatable { let content: Content }
    struct RenderedPeer: Equatable { let peerId: Int64 }
    struct Data: Equatable { let renderedPeer: RenderedPeer }
    let promoInfo: Promo
    let item: Data

    init(_ id: Int64, _ content: Content) {
        self.promoInfo = Promo(content: content)
        self.item = Data(renderedPeer: RenderedPeer(peerId: id))
    }
}

struct ListState { let hiddenPsaPeerId: Int64? }

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let mode = CommandLine.arguments[1]
let suite = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
let settings = DGSimpleSettings(defaults: defaults)

if mode == "write" {
    defaults.removePersistentDomain(forName: suite)
    check(!settings.hideProxySponsor && !settings.roundVideoCountdown, "new settings are opt-in")
    check(settings.localVerification(accountId: 1) == .none, "no local verification by default")
    settings.setLocalVerification(.major, accountId: 1)
    settings.setLocalVerification(.hold, accountId: 2)
    check(settings.localVerification(accountId: 4) == .none, "verification must not leak to another account")
    settings.setLocalVerification(.crow, accountId: 4)
    defaults.set("123", forKey: "donutgram.profile.verificationIcon.major")
    defaults.set("{\"iconFileId\":123,\"botId\":456,\"description\":\"stale\"}", forKey: "donutgram.profile.verificationDetails.major")
    check(settings.localVerificationIcon(.major) == 5909078961467431777, "stale lookup caches cannot override the confirmed icon")

    let items = [Item(10, .proxy), Item(20, .psa), Item(30, .psa)]
    let state = ListState(hiddenPsaPeerId: 30)
    check(filterItems(items, settings: settings, state: state) == [items[0], items[1]], "existing PSA hiding is preserved")
    settings.hideProxySponsor = true
    check(filterItems(items, settings: settings, state: state) == [items[1]], "only proxy promotions are removed")
    settings.hideProxySponsor = false
    check(filterItems(items, settings: settings, state: state) == [items[0], items[1]], "proxy sponsor can be restored")
    settings.hideProxySponsor = true
    settings.roundVideoCountdown = true
    defaults.synchronize()
} else {
    check(settings.hideProxySponsor && settings.roundVideoCountdown, "switches survive relaunch")
    check(settings.localVerification(accountId: 1) == .major, "major survives relaunch")
    check(settings.localVerification(accountId: 2) == .hold, "hold survives relaunch")
    check(settings.localVerification(accountId: 3) == .none, "another account stays without a badge")
    check(settings.localVerification(accountId: 4) == .crow, "local verification survives relaunch")
    settings.setLocalVerification(.none, accountId: 1)
    check(settings.localVerification(accountId: 1) == .none && settings.localVerification(accountId: 2) == .hold, "disabling one account leaves another unchanged")
    defaults.removePersistentDomain(forName: suite)
}

let expectedVerification: [(DGLocalVerification, Int64, Int64, String)] = [
    (.hold, 5913729775393840687, 8365813836, "This user was verified by the organization \"Hold\"."),
    (.major, 5909078961467431777, 7487372978, "This user was verified by the organization \"Major\"."),
    (.crow, 5800995289124838177, 8217627596, "This account is verified as official by the representatives of Telegram.")
]
check(DGLocalVerification.allCases == [.none, .major, .hold, .crow], "only the requested verification choices are available")
for (selection, iconId, botId, description) in expectedVerification {
    check(settings.localVerificationDetails(selection) == DGLocalVerificationDetails(iconFileId: iconId, botId: botId, description: description), "confirmed icon, verifier and description are available without a profile lookup")
    check(settings.localVerificationIcon(selection) == iconId, "the complete 64-bit emoji id is used for rendering")
}
check(settings.localVerificationDetails(.none) == nil && settings.localVerificationIcon(.none) == nil, "disabled verification has no icon or description")

private var countdown = RoundVideoRecordingCountdown()
check(countdown.remaining(at: 100) == nil, "countdown starts inactive")
countdown.start(at: 100)
for (time, value) in [(100.0, 3), (100.999, 3), (101.0, 2), (101.999, 2), (102.0, 1), (102.999, 1), (103.0, 0), (120.0, 0)] {
    check(countdown.remaining(at: time) == value, "countdown uses elapsed time, including delayed timer ticks")
}
countdown.cancel()
check(countdown.remaining(at: 121) == nil, "cancelled countdown cannot start recording")
countdown.start(at: 200)
check(countdown.remaining(at: 200) == 3 && countdown.remaining(at: 203) == 0, "new recording gets a fresh countdown")
countdown.cancel()
print("local profile, proxy sponsor and countdown behavior checks passed")
