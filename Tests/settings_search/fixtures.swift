func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func ids(_ query: String, hasIsland: Bool = true) -> Set<String> {
    return Set(dgSettingsSearchItems(query: query, hasIsland: hasIsland).map { $0.id })
}

let suite = "donutgram-settings-search-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
let testSettings = DGSimpleSettings(defaults: defaults)
defer { defaults.removePersistentDomain(forName: suite) }

check(ids("").isEmpty && ids(" \n  ").isEmpty && ids("?!—").isEmpty, "empty queries never return every feature")
check(ids("zzzxxyy").isEmpty, "unknown query has no results")
check(ids("  СПОНСОРА   прокси ") == ["ads-and-gifts/hideProxySponsor"], "case, whitespace and word order")
check(ids("proxy sponsor") == ["ads-and-gifts/hideProxySponsor"], "English titles are searchable")
check(ids("прокси sponsor") == ["ads-and-gifts/hideProxySponsor"], "mixed-language queries")
check(ids("отсчет") == ids("отсчёт") && ids("отсчет").contains("media/roundVideoCountdown"), "yo and ye match")
check(ids("свои удаленные").contains("saving/saveOwnDeleted"), "dependent settings stay searchable while disabled")
check(ids("format id").contains("profiles/dialogIdFormat"), "hidden format setting is indexed")
check(ids("автопауза кружки") == ["media/autoPauseRound"], "section and title words combine")
check(ids("pause music voice").contains("media/pauseMusicVoiceRecording"), "English section names participate")
check(ids("призрак").contains("ghost/messages"), "section searches include their settings")
check(ids("размер стикеров").contains("stickers/stickerSize"), "custom sliders are indexed")
check(ids("blocked").contains("shadow-ban/hideBlocked"), "blocked-message switch is indexed")
check(ids("уровень").contains("visual-rating/level"), "nested editors are indexed")
check(ids("остров", hasIsland: false).isEmpty, "unsupported island settings stay hidden")
check(ids("island", hasIsland: true).contains("icon-and-island/islandStyle"), "island styles are searchable on supported devices")
check(ids("app icon", hasIsland: false).contains("icon-and-island/appIcon"), "icon picker remains searchable without an island")
let all = dgSettingsSearchCatalog
check(Set(all.map { $0.id }).count == all.count, "result routes must be unique")
check(Set(all.map { $0.index }).count == all.count, "list identities must be unique")
check(all.allSatisfy { DGSettingsPage(rawValue: $0.page) != nil }, "every result targets a known page")
check(dgSettingsSearchItems(query: "proxy", hasIsland: true).first?.path(languageCode: "en").contains("Ads and Gifts") == true, "result paths use the selected language")
testSettings.saveDeletedMessages = false
testSettings.saveEditHistory = false
testSettings.showProfileId = false
testSettings.autoPause = false
testSettings.disableMediaAutoplay = false
testSettings.downloadTikTok = false
testSettings.downloadYouTubeShorts = false
testSettings.islandFollowsIcon = true
for (page, key, parent) in [(DGSettingsPage.saving, "saveOwnDeleted", "saveDeleted"), (.saving, "saveBots", "saveDeleted"), (.profiles, "dialogIdFormat", "profileId"), (.media, "autoPauseRound", "autoPause"), (.media, "autoplayVoice", "autoplayMedia"), (.downloads, "signDownloads", "downloadTikTok"), (.iconAndIsland, "islandStyle", "islandFollowsIcon")] {
    check(dgShownRow(page: page, key: key) == parent, "hidden results focus their parent without changing settings")
}
testSettings.saveDeletedMessages = true
testSettings.islandFollowsIcon = false
check(dgShownRow(page: .saving, key: "saveOwnDeleted") == "saveOwnDeleted", "shown settings focus the result itself")
check(dgShownRow(page: .iconAndIsland, key: "islandStyle") == "islandStyle", "shown island picker focuses itself")
print("settings search behavior and navigation checks passed")
