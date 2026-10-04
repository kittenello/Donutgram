# Теневой бан — план реализации

> **Для исполнителей-агентов:** обязательный навык — superpowers:subagent-driven-development (рекомендуется) или
> superpowers:executing-plans. Шаги размечены чекбоксами (`- [ ]`).

**Цель:** локальный теневой бан. Сообщения забаненного (человека, бота или канала) скрыты в группах, комментариях,
каналах и чате «Ответы». Там же скрыты его «печатает…», аватарки на реакциях и под постами и его сторис.

**Архитектура:** фильтр на уровне отображения.
- Список хранится в `DGSimpleSettings`.
- Правило «скрыто ли» живёт одной чистой функцией в TelegramCore (`DonutgramShadowBan`).
- Каждое место интерфейса (лента, список чатов, цитаты, уведомления, поиск, закреп, «печатает…», реакции, сторис)
  спрашивает это правило.
- Лента получает отдельные починки подгрузки и прочтения. Они включаются, только если в окне что-то скрыто.

**Стек:** Swift, Bazel (`Make.py`), SwiftSignalKit, Postbox/TelegramCore, ItemListUI, AsyncDisplayKit.

**Спек:** `docs/superpowers/specs/2026-10-04-shadow-ban-design.md`. Исполнитель читает его вместе с планом.

## Глобальные ограничения

- Весь видимый пользователю текст — на русском, строки дословно:
  - пункты меню: «Теневой бан», «Убрать из теневого бана», «Показать скрытые сообщения», «Спрятать скрытые сообщения»;
  - тосты: «<Имя> в теневом бане», «<Имя> убран из теневого бана», кнопка «Отменить»;
  - страница настроек: «Добавить», «Неизвестный», «Выключен»;
  - подпись внизу страницы: «Сообщения этих людей скрыты в группах, комментариях и каналах только на этом устройстве.
    Они об этом не узнают. Личные чаты не меняются.»
- Комментарии в коде — на английском, в стиле соседнего кода форка.
- `TelegramCore`, `DGSimpleSettings` и `DGSettingsUI` собираются с `-warnings-as-errors`. Поэтому нельзя оставлять:
  - неиспользуемые `let`/`var`;
  - `var`, который нигде не меняется;
  - результат функции без `let _ =`;
  - `default:` в `switch`, где все случаи уже перечислены.
- TelegramCore не импортирует UIKit и Display (правило 7 CLAUDE.md).
- Новых `import Postbox` в модулях, где его не было, не добавлять: там используются `EngineMessage`/`EnginePeer`.
- **Коммитов и пушей нет** до команды пользователя. Ворктри: `.claude/worktrees/shadow-ban`, ветка `feat/shadow-ban`.
  Задачи заканчиваются контрольной точкой, а не коммитом. Пять коммитов делает задача 9, только по команде.
- Файлы ворктри с CRLF. Инструмент Edit годится. Скриптовые правки должны учитывать `\r\n`. На каждой контрольной
  точке запускать `git diff --check`.
- Сборки и тестов локально нет: Windows, без Bazel и Xcode. Компиляцию проверяет только CI-сборка PR
  (`build.yml`, 40–60 мин). XCTest из `Donutgram/DGFeatureTests` запускаются только на Маке:
  `Make.py test --target //Donutgram/DGFeatureTests:DGFeatureTests`. В этой среде шаги «запусти тест» заменены
  внимательной сверкой ожидаемого результата.
- В харнесе ворктри Bash отказывается выполнять команды с переменными (`$X`) и `cd` в другие места. Нужны простые
  команды с литеральными путями.

## Отличия от спека

- У `isPeerHidden` нет параметра `chatPeer`: решение всегда принимается по ID чата. Поэтому для «печатает…» и
  аватарок monoforum считается каналом. Спек допускает это для случая без объекта чата, а сам объект чата там почти
  нигде не доступен.
- Разбивка по коммитам сдвинута в двух местах, причины — в задаче 9.

## Фокус проверки

Пять отказов, которые тесты задач не ловят целиком, по убыванию вероятности:

1. **Всё окно истории скрыто.**
   - Ожидается: при открытии чата загрузка, затем видимые сообщения. Без заглушки «нет сообщений», без бесконечного
     спиннера и без качелей между двумя окнами.
   - Если скрыт весь чат — заглушка «нет сообщений».
   - Тесты `HiddenWindowWalk` в задаче 1 и проверка на телефоне в задаче 9.
2. **Последнее сообщение группы от забаненного.**
   - Ожидается: после открытия группы и при сидении внизу бейдж непрочитанного у группы гаснет. Скрытое сообщение,
     пришедшее при открытом чате, тоже читается.
   - Тест `readIndexPastHidden` в задаче 1 и проверка на телефоне в задаче 9.
3. **Строка темы форума или «Архив» со скрытым последним сообщением.**
   - Ожидается: тап открывает ту же тему.
   - Поэтому превью чистится в раскладке строки, а не в записи списка. Проверка в задаче 3.
4. **Бан или «Показать скрытые» при открытом чате.**
   - Ожидается: сообщения уезжают или возвращаются без прыжка скролла, а шапки ответов обновляются.
   - Проверка в задаче 2.
5. **Включён режим призрака.**
   - Ожидается: прочтение скрытых не отправляет отметку «прочитано».
   - Всё идёт через `applyMaxReadIndex`. Проверка в задаче 9.

---

### Task 1: хранение, правило и чистые помощники (коммит 1)

**Файлы:**
- Изменить: `Donutgram/DGSimpleSettings/Sources/DGSimpleSettings.swift`
- Создать: `submodules/TelegramCore/Sources/Donutgram/DonutgramShadowBan.swift`
- Создать тест: `Donutgram/DGFeatureTests/Tests/ShadowBanTests.swift`

**Интерфейсы:**
- Даёт `DGSimpleSettings`:
  - `static let shadowBanDidChangeNotification`;
  - `var shadowBannedPeerIds: Set<Int64>`, `var hasShadowBans: Bool`;
  - `func isShadowBanned(_ peerId: Int64) -> Bool`, `func setShadowBanned(_ banned: Bool, peerId: Int64)`;
  - `var shadowBanRevealedChatIds: Set<Int64>`;
  - `func isShadowBanRevealed(chatPeerId: Int64) -> Bool`, `func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64)`.
- Даёт `DonutgramShadowBan`, используют все следующие задачи:
  - тип `State` и `State.current`, сигнал `stateSignal()`;
  - `appliesToChat(_:chatPeer:)`, `appliesToChat(_ chatPeer: EnginePeer)`;
  - `isBannedContent(_:bannedPeerIds:)`, `isBannedContent(_:)`;
  - `isHidden(_: Message, state:)`, `isHidden(_: Message)`, `isHidden(_: EngineMessage)`;
  - `isPeerHidden(_:inChat:state:)`, `hidesReplyHeader(in:)`;
  - `banTarget(of:)`, `canBan(_:accountPeerId:)`;
  - `filteringHidden(_: SearchMessagesResult)`, `filteringHidden(_: EngineStorySubscriptions, state:)`;
  - `readIndexPastHidden(_:visibleIndices:windowIndices:)`;
  - типы `HiddenWindowDirection` и `HiddenWindowWalk` с методом `next(canLoadEarlier:canLoadLater:)`.

- [ ] **Шаг 1: написать тесты (они падают — `DonutgramShadowBan` ещё нет)**

Создать `Donutgram/DGFeatureTests/Tests/ShadowBanTests.swift`:

```swift
import XCTest
import Postbox
import TelegramCore
import DGSimpleSettings

final class ShadowBanTests: XCTestCase {
    private let alice = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(101))
    private let bob = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(102))
    private let bot = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(103))
    private let supergroup = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(201))
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(202))
    private let monoforum = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(203))
    private let otherChannel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(204))
    private let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(301))
    private let secretChat = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(401))
    private let replies = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1271266957))

    private func user(_ id: PeerId) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channelPeer(_ id: PeerId, broadcast: Bool, flags: TelegramChannelFlags = []) -> TelegramChannel {
        let info: TelegramChannelInfo = broadcast ? .broadcast(TelegramChannelBroadcastInfo(flags: [])) : .group(TelegramChannelGroupInfo(flags: []))
        return TelegramChannel(id: id, accessHash: nil, title: "Chat", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: info, flags: flags, restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func forward(author: Peer?, source: Peer? = nil) -> MessageForwardInfo {
        return MessageForwardInfo(author: author, source: source, sourceMessageId: nil, date: 0, authorSignature: nil, psaType: nil, flags: [])
    }

    private func message(in chatPeerId: PeerId, chatPeer: Peer? = nil, author: Peer?, incoming: Bool = true, forwardInfo: MessageForwardInfo? = nil, attributes: [MessageAttribute] = [], media: [Media] = []) -> Message {
        var peers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer {
            peers[chatPeer.id] = chatPeer
        }
        if let author {
            peers[author.id] = author
        }
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: chatPeerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo, author: author, text: "", attributes: attributes, media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(banned: [PeerId], revealed: [PeerId] = []) -> DonutgramShadowBan.State {
        return DonutgramShadowBan.State(bannedPeerIds: Set(banned.map { $0.toInt64() }), revealedChatIds: Set(revealed.map { $0.toInt64() }))
    }

    private func index(_ id: Int32) -> MessageIndex {
        return MessageIndex(id: MessageId(peerId: self.supergroup, namespace: Namespaces.Message.Cloud, id: id), timestamp: id)
    }

    func testBannedAuthorIsHiddenInSupergroupAndGroup() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice)), state: state))
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.group, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob)), state: state))
    }

    func testPrivateAndSecretChatsAreNeverFiltered() {
        let state = self.state(banned: [self.alice])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.alice, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.secretChat, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.bob, author: self.user(self.bob), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
    }

    func testOwnMessagesAreNeverHidden() {
        let state = self.state(banned: [self.alice])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice), incoming: false), state: state))
    }

    func testForwardsFromBannedAuthorOrSourceAreHidden() {
        let state = self.state(banned: [self.alice, self.channel])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
        let source = self.channelPeer(self.channel, broadcast: true)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.otherChannel, author: self.channelPeer(self.otherChannel, broadcast: true), forwardInfo: self.forward(author: nil, source: source)), state: state))
    }

    func testViaBannedInlineBotIsHidden() {
        let state = self.state(banned: [self.bot])
        let viaBot = InlineBotMessageAttribute(peerId: self.bot, title: nil)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob), attributes: [viaBot]), state: state))
    }

    func testBannedChannelOwnPostsStayVisible() {
        let state = self.state(banned: [self.channel])
        let bannedChannel = self.channelPeer(self.channel, broadcast: true)
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.channel, chatPeer: bannedChannel, author: bannedChannel), state: state))
    }

    func testServiceMessageFromBannedAuthorIsHidden() {
        let state = self.state(banned: [self.alice])
        let action = TelegramMediaAction(action: .pinnedMessageUpdated)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice), media: [action]), state: state))
    }

    func testRepliesChatIsFiltered() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.replies, author: self.user(self.replies), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
    }

    func testMonoforumIsNotFiltered() {
        let state = self.state(banned: [self.alice])
        let monoforumPeer = self.channelPeer(self.monoforum, broadcast: false, flags: [.isMonoforum])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.monoforum, chatPeer: monoforumPeer, author: self.user(self.alice)), state: state))
    }

    func testRevealedChatShowsMessagesButKeepsBannedContent() {
        let state = self.state(banned: [self.alice], revealed: [self.supergroup])
        let message = self.message(in: self.supergroup, author: self.user(self.alice))
        XCTAssertFalse(DonutgramShadowBan.isHidden(message, state: state))
        XCTAssertTrue(DonutgramShadowBan.isBannedContent(message, bannedPeerIds: state.bannedPeerIds))
    }

    func testEmptyListHidesNothing() {
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice)), state: self.state(banned: [])))
    }

    func testPeerIsHiddenOnlyInFilteredChats() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.supergroup, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.alice, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.bob, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.supergroup, state: self.state(banned: [self.alice], revealed: [self.supergroup])))
    }

    func testReadIndexMovesOverTrailingHiddenMessages() {
        let window = [self.index(1), self.index(2), self.index(3), self.index(4), self.index(5)]
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(2), visibleIndices: [self.index(1), self.index(2), self.index(5)], windowIndices: window), self.index(4))
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(2), visibleIndices: [self.index(1), self.index(2)], windowIndices: window), self.index(5))
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(5), visibleIndices: [self.index(5)], windowIndices: window), self.index(5))
    }

    func testHiddenWindowWalkKeepsDirectionAndTurnsOnce() {
        var fromBottom = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: false), .earlier)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: true), .earlier)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: false, canLoadLater: true), .later)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: true), .later)
        XCTAssertNil(fromBottom.next(canLoadEarlier: true, canLoadLater: false))

        var fromMiddle = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertEqual(fromMiddle.next(canLoadEarlier: true, canLoadLater: true), .later)

        var wholeChatHidden = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertNil(wholeChatHidden.next(canLoadEarlier: false, canLoadLater: false))
    }

    func testStorageRoundTrip() {
        let settings = DGSimpleSettings.shared
        let peerId = self.alice.toInt64()
        let wasBanned = settings.isShadowBanned(peerId)
        defer {
            settings.setShadowBanned(wasBanned, peerId: peerId)
        }
        settings.setShadowBanned(true, peerId: peerId)
        XCTAssertTrue(settings.isShadowBanned(peerId))
        XCTAssertTrue((UserDefaults.standard.stringArray(forKey: "donutgram.spy.shadowBannedPeerIds") ?? []).contains(String(peerId)))
        settings.setShadowBanned(false, peerId: peerId)
        XCTAssertFalse(settings.isShadowBanned(peerId))
        XCTAssertFalse(settings.isShadowBanRevealed(chatPeerId: self.supergroup.toInt64()))
    }
}
```

- [ ] **Шаг 2: сверить, что тесты не собираются без реализации**

На Маке: `Make.py test --target //Donutgram/DGFeatureTests:DGFeatureTests`, ожидается ошибка сборки
`cannot find 'DonutgramShadowBan' in scope`. Здесь запуска нет: проверить вызовом
`grep -rn "enum DonutgramShadowBan" submodules/TelegramCore/Sources`, что символа ещё нет (вывод пустой).

Заодно сверить три конструктора, от которых зависят тесты. Каждая команда должна найти совпадение:
```bash
grep -n "case pinnedMessageUpdated" submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaAction.swift
```
```bash
grep -n "public init(peerId: PeerId?, title: String?)" submodules/TelegramCore/Sources/SyncCore/SyncCore_InlineBotMessageAttribute.swift
```
```bash
grep -n "public init(id: MessageId, timestamp: Int32)" submodules/Postbox/Sources/Message.swift
```
Если какой-то не найден, взять действующую сигнатуру из файла и поправить тест.

- [ ] **Шаг 3: хранение в `DGSimpleSettings`**

В `public final class DGSimpleSettings` рядом с другими `Notification.Name` добавить:

```swift
    /// The shadow ban list or a chat's «Показать скрытые» changed. Separate from didChangeNotification, which makes presence
    /// send account.updateStatus.
    public static let shadowBanDidChangeNotification = Notification.Name("donutgram.shadowBan.didChange")
```

В `private enum Key` после `static let localPremiumPeerIds = …` добавить:

```swift
        static let shadowBannedPeerIds = "donutgram.spy.shadowBannedPeerIds"
```

После `setLocalPremium(_:accountId:)` добавить:

```swift
    private let shadowBanLock = NSLock()
    private var shadowBanCache: Set<Int64>?
    private var shadowBanRevealedChats = Set<Int64>()

    // Call with shadowBanLock held.
    private func shadowBanIdsLocked() -> Set<Int64> {
        if let cache = self.shadowBanCache {
            return cache
        }
        let stored = Set((self.defaults.stringArray(forKey: Key.shadowBannedPeerIds) ?? []).compactMap { Int64($0) })
        self.shadowBanCache = stored
        return stored
    }

    /// Peers in the shadow ban, as `PeerId.toInt64()`, for every account: their messages are hidden in groups, channels and comments.
    public var shadowBannedPeerIds: Set<Int64> {
        self.shadowBanLock.lock()
        defer { self.shadowBanLock.unlock() }
        return self.shadowBanIdsLocked()
    }

    public var hasShadowBans: Bool {
        return !self.shadowBannedPeerIds.isEmpty
    }

    public func isShadowBanned(_ peerId: Int64) -> Bool {
        return self.shadowBannedPeerIds.contains(peerId)
    }

    public func setShadowBanned(_ banned: Bool, peerId: Int64) {
        self.shadowBanLock.lock()
        var ids = self.shadowBanIdsLocked()
        let changed = banned ? ids.insert(peerId).inserted : ids.remove(peerId) != nil
        if changed {
            self.shadowBanCache = ids
            self.defaults.set(ids.map { String($0) }.sorted(), forKey: Key.shadowBannedPeerIds)
        }
        self.shadowBanLock.unlock()
        if changed {
            NotificationCenter.default.post(name: DGSimpleSettings.shadowBanDidChangeNotification, object: self)
        }
    }

    /// Chats where «Показать скрытые» is on, as `PeerId.toInt64()`: in memory only, until the app restarts.
    public var shadowBanRevealedChatIds: Set<Int64> {
        self.shadowBanLock.lock()
        defer { self.shadowBanLock.unlock() }
        return self.shadowBanRevealedChats
    }

    public func isShadowBanRevealed(chatPeerId: Int64) -> Bool {
        return self.shadowBanRevealedChatIds.contains(chatPeerId)
    }

    public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64) {
        self.shadowBanLock.lock()
        let changed = revealed ? self.shadowBanRevealedChats.insert(chatPeerId).inserted : self.shadowBanRevealedChats.remove(chatPeerId) != nil
        self.shadowBanLock.unlock()
        if changed {
            NotificationCenter.default.post(name: DGSimpleSettings.shadowBanDidChangeNotification, object: self)
        }
    }
```

- [ ] **Шаг 4: правило в TelegramCore**

Создать `submodules/TelegramCore/Sources/Donutgram/DonutgramShadowBan.swift`. Сборка подхватит его через `glob` в
`submodules/TelegramCore/BUILD`.

```swift
import Foundation
import Postbox
import SwiftSignalKit
import DGSimpleSettings

/// Local shadow ban. Messages of the peers in `DGSimpleSettings.shadowBannedPeerIds` are hidden in groups, channels,
/// comments and the Replies chat, with their typing, reaction avatars and stories. Private chats are never filtered,
/// and nothing goes to the server: the person never learns about it.
public enum DonutgramShadowBan {
    /// The ban list and the chats with «Показать скрытые» on, read once for a whole computation.
    public struct State: Equatable {
        public var bannedPeerIds: Set<Int64>
        public var revealedChatIds: Set<Int64>

        public init(bannedPeerIds: Set<Int64>, revealedChatIds: Set<Int64>) {
            self.bannedPeerIds = bannedPeerIds
            self.revealedChatIds = revealedChatIds
        }

        public static var current: State {
            let settings = DGSimpleSettings.shared
            return State(bannedPeerIds: settings.shadowBannedPeerIds, revealedChatIds: settings.shadowBanRevealedChatIds)
        }
    }

    /// The current state, then every change of the list or of «Показать скрытые».
    public static func stateSignal() -> Signal<State, NoError> {
        return Signal<State, NoError> { subscriber in
            subscriber.putNext(State.current)
            let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.shadowBanDidChangeNotification, object: nil, queue: nil, using: { _ in
                subscriber.putNext(State.current)
            })
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        |> distinctUntilChanged
    }

    /// Groups, supergroups, forums, channels with their discussions, and the Replies chat. Private chats, bots, secret
    /// chats, Saved Messages and direct messages to a channel (monoforum) are never filtered.
    public static func appliesToChat(_ chatPeerId: PeerId, chatPeer: Peer?) -> Bool {
        if chatPeerId.namespace == Namespaces.Peer.CloudGroup {
            return true
        } else if chatPeerId.namespace == Namespaces.Peer.CloudChannel {
            if let chatPeer, chatPeer.isMonoForum {
                return false
            }
            return true
        } else if chatPeerId.namespace == Namespaces.Peer.CloudUser {
            return chatPeerId.isReplies
        } else {
            return false
        }
    }

    public static func appliesToChat(_ chatPeer: EnginePeer) -> Bool {
        return self.appliesToChat(chatPeer.id, chatPeer: chatPeer._asPeer())
    }

    /// Whether `message` comes from a banned author in a filtered chat, ignoring «Показать скрытые»: the sender, the
    /// forwarded author or source, or the inline bot. The chat itself never counts, so a banned channel's own posts stay
    /// visible in that channel.
    public static func isBannedContent(_ message: Message, bannedPeerIds: Set<Int64>) -> Bool {
        if bannedPeerIds.isEmpty {
            return false
        }
        let chatPeerId = message.id.peerId
        if !message.flags.contains(.Incoming) || !self.appliesToChat(chatPeerId, chatPeer: message.peers[chatPeerId]) {
            return false
        }
        let isBanned: (PeerId?) -> Bool = { peerId in
            guard let peerId, peerId != chatPeerId else {
                return false
            }
            return bannedPeerIds.contains(peerId.toInt64())
        }
        if isBanned(message.author?.id) {
            return true
        }
        if let forwardInfo = message.forwardInfo, isBanned(forwardInfo.author?.id) || isBanned(forwardInfo.source?.id) {
            return true
        }
        for attribute in message.attributes {
            if let attribute = attribute as? InlineBotMessageAttribute, isBanned(attribute.peerId) {
                return true
            }
        }
        return false
    }

    public static func isBannedContent(_ message: Message) -> Bool {
        return self.isBannedContent(message, bannedPeerIds: DGSimpleSettings.shared.shadowBannedPeerIds)
    }

    /// Whether `message` is hidden: banned content in a chat without «Показать скрытые».
    public static func isHidden(_ message: Message, state: State) -> Bool {
        if state.bannedPeerIds.isEmpty || state.revealedChatIds.contains(message.id.peerId.toInt64()) {
            return false
        }
        return self.isBannedContent(message, bannedPeerIds: state.bannedPeerIds)
    }

    public static func isHidden(_ message: Message) -> Bool {
        if !DGSimpleSettings.shared.hasShadowBans {
            return false
        }
        return self.isHidden(message, state: State.current)
    }

    public static func isHidden(_ message: EngineMessage) -> Bool {
        return self.isHidden(message._asMessage())
    }

    /// Whether to hide `peerId`'s typing and avatars in a chat. Decided by the chat's id alone, so a monoforum counts as a
    /// channel here.
    public static func isPeerHidden(_ peerId: PeerId, inChat chatPeerId: PeerId, state: State = State.current) -> Bool {
        if state.bannedPeerIds.isEmpty || peerId == chatPeerId || state.revealedChatIds.contains(chatPeerId.toInt64()) {
            return false
        }
        if !self.appliesToChat(chatPeerId, chatPeer: nil) {
            return false
        }
        return state.bannedPeerIds.contains(peerId.toInt64())
    }

    /// Whether to drop the reply header of `message`: it quotes a hidden message or, for a reply to another chat where
    /// only the author is known, a banned author.
    public static func hidesReplyHeader(in message: Message) -> Bool {
        if !DGSimpleSettings.shared.hasShadowBans {
            return false
        }
        let state = State.current
        for attribute in message.attributes {
            if let attribute = attribute as? ReplyMessageAttribute {
                if let replyMessage = message.associatedMessages[attribute.messageId] {
                    return self.isHidden(replyMessage, state: state)
                }
            } else if let attribute = attribute as? QuotedReplyMessageAttribute, let authorId = attribute.peerId {
                return self.isPeerHidden(authorId, inChat: message.id.peerId, state: state)
            }
        }
        return false
    }

    /// Who a message's ban applies to: the sender, or the reply's author in the Replies chat.
    public static func banTarget(of message: Message) -> Peer? {
        if message.id.peerId.isReplies {
            return message.forwardInfo?.author
        }
        return message.author
    }

    /// People, bots and channels can be banned; groups and the account itself can't.
    public static func canBan(_ peer: EnginePeer, accountPeerId: PeerId) -> Bool {
        if peer.id == accountPeerId {
            return false
        }
        switch peer {
        case .user:
            return true
        case let .channel(channel):
            if case .broadcast = channel.info {
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Search results without hidden messages; the total shrinks by the dropped ones.
    public static func filteringHidden(_ result: SearchMessagesResult) -> SearchMessagesResult {
        if !DGSimpleSettings.shared.hasShadowBans {
            return result
        }
        let state = State.current
        let messages = result.messages.filter { !self.isHidden($0, state: state) }
        if messages.count == result.messages.count {
            return result
        }
        let dropped = Int32(result.messages.count - messages.count)
        return SearchMessagesResult(messages: messages, readStates: result.readStates, threadInfo: result.threadInfo, totalCount: max(0, result.totalCount - dropped), completed: result.completed)
    }

    /// Story subscriptions without banned peers; the account's own stories stay.
    public static func filteringHidden(_ subscriptions: EngineStorySubscriptions, state: State) -> EngineStorySubscriptions {
        if state.bannedPeerIds.isEmpty {
            return subscriptions
        }
        let items = subscriptions.items.filter { !state.bannedPeerIds.contains($0.peer.id.toInt64()) }
        if items.count == subscriptions.items.count {
            return subscriptions
        }
        return EngineStorySubscriptions(accountItem: subscriptions.accountItem, items: items, hasMoreToken: subscriptions.hasMoreToken)
    }

    /// The read index moved over hidden messages: the last index in `windowIndices` above `index` and below the first
    /// visible index above `index`, or up to the window's end when nothing visible follows. Both arrays are ascending.
    public static func readIndexPastHidden(_ index: MessageIndex, visibleIndices: [MessageIndex], windowIndices: [MessageIndex]) -> MessageIndex {
        let nextVisibleIndex = visibleIndices.first(where: { $0 > index })
        var result = index
        for windowIndex in windowIndices {
            if windowIndex <= result {
                continue
            }
            if let nextVisibleIndex, windowIndex >= nextVisibleIndex {
                break
            }
            result = windowIndex
        }
        return result
    }

    public enum HiddenWindowDirection: Equatable {
        case earlier
        case later
    }

    /// Walks the history past windows where every message is hidden, so a chat doesn't show «no messages» while it has
    /// visible ones elsewhere. It keeps one direction (newer when there is something newer, otherwise older) and turns
    /// around once at that end; nil means nothing is left to load, so the chat has no visible messages.
    public struct HiddenWindowWalk: Equatable {
        public private(set) var direction: HiddenWindowDirection?
        private var hasTurned = false

        public init() {
        }

        public mutating func next(canLoadEarlier: Bool, canLoadLater: Bool) -> HiddenWindowDirection? {
            let canLoad: (HiddenWindowDirection) -> Bool = { direction in
                switch direction {
                case .earlier:
                    return canLoadEarlier
                case .later:
                    return canLoadLater
                }
            }
            let direction = self.direction ?? (canLoadLater ? .later : .earlier)
            if canLoad(direction) {
                self.direction = direction
                return direction
            }
            if self.hasTurned {
                return nil
            }
            self.hasTurned = true
            let turned: HiddenWindowDirection = direction == .earlier ? .later : .earlier
            self.direction = turned
            return canLoad(turned) ? turned : nil
        }
    }
}
```

- [ ] **Шаг 5: сверить тесты с реализацией (вместо запуска)**

Пройти каждый тест по коду из шага 4 и убедиться, что ожидания совпадают. Особенно:
- `testHiddenWindowWalkKeepsDirectionAndTurnsOnce`: earlier, earlier, затем поворот на later, later, затем nil;
- `testReadIndexMovesOverTrailingHiddenMessages`: результаты 4, 5 и 5.

На Маке: `Make.py test --target //Donutgram/DGFeatureTests:DGFeatureTests`, ожидается
`Executed 14 tests, with 0 failures`.

- [ ] **Шаг 6: контрольная точка**

```bash
git diff --check
```
```bash
git status --short
```
Ожидается: `git diff --check` ничего не выводит. В статусе изменён `DGSimpleSettings.swift`, новые файлы —
`DonutgramShadowBan.swift` и `ShadowBanTests.swift`, плюс уже лежащие спек и план. Коммита нет.

---

### Task 2: лента сообщений (коммит 2)

**Файлы:**
- Изменить: `submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift` — сигнатура (L36–64), цикл (L143–155),
  возвраты (L68, L844, L848, L853).
- Изменить: `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`:
  - структура `ChatHistoryView` (L82–91);
  - промисы (L648–655, L1850–1858, L1970);
  - вызов функции записей (L2244–2274);
  - наблюдатель (L1290–1310) и `deinit` (L1312);
  - прочтение (L1195–1197);
  - подгрузка (L3458–3525);
  - упоминания (L2967 и L3297);
  - применение перехода (L4202–4290).
- Изменить: `submodules/TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift` — `setupItem` (L690–696).

**Интерфейсы:**
- Берёт из задачи 1: `DonutgramShadowBan.State`, `isHidden(_:state:)`, `isHidden(_:)`, `isBannedContent(_:)`,
  `readIndexPastHidden(...)`, `HiddenWindowWalk`, `DGSimpleSettings.shadowBanDidChangeNotification`,
  `isShadowBanRevealed(chatPeerId:)`.
- Даёт:
  - `chatHistoryEntriesForView(..., shadowBan: DonutgramShadowBan.State?, ...) -> ([ChatHistoryEntry], ChatHistoryEntriesForViewState, Int)`
    (третье значение — число скрытых);
  - `ChatHistoryView.donutgramHiddenCount: Int`.

- [ ] **Шаг 1: фильтр в `chatHistoryEntriesForView`**

В сигнатуре после `pendingRemovedMessages: Set<MessageId>,` добавить параметр и поменять тип результата:

```swift
    pendingRemovedMessages: Set<MessageId>,
    shadowBan: DonutgramShadowBan.State?,
```
```swift
) -> ([ChatHistoryEntry], ChatHistoryEntriesForViewState, Int) {
```

Возвраты:
- `return ([], currentState)` в начале функции (L68) заменить на `return ([], currentState, 0)`.
- В конце (L844, L848, L853) заменить на `return ([], currentState, donutgramHiddenCount)`,
  `return (entries.reversed(), currentState, donutgramHiddenCount)` и `return (entries, currentState, donutgramHiddenCount)`.

Перед `loop: for entry in view.entries {` (после `var count = 0`) добавить:

```swift
    // Shadow-banned messages are skipped before grouping, so a banned author's album goes away whole.
    var donutgramHiddenCount = 0
```

Сразу после блока `if pendingRemovedMessages.contains(message.id) { continue }` добавить:

```swift
        if let shadowBan, DonutgramShadowBan.isHidden(message, state: shadowBan) {
            donutgramHiddenCount += 1
            continue
        }
```

Корневое сообщение треда (блок около L463–524 из `view.additionalData`) не трогать.

- [ ] **Шаг 2: `ChatHistoryView` и промис состояния**

В `struct ChatHistoryView` последней строкой добавить:

```swift
    // Messages of this window hidden by the shadow ban; the loading and read fixes below run only when it's above zero.
    var donutgramHiddenCount: Int = 0
```

После `pendingRemovedMessages` (L648–655) добавить свойства:

```swift
    private let donutgramShadowBanPromise = ValuePromise<DonutgramShadowBan.State>(DonutgramShadowBan.State.current, ignoreRepeated: true)
    private var donutgramShadowBanObserver: NSObjectProtocol?
    private var donutgramHiddenWindowWalk = DonutgramShadowBan.HiddenWindowWalk()
```

В `let promises = combineLatest(` (L1850) после `self.allAdMessagesPromise.get()` добавить восьмой сигнал. Главный
`combineLatest` уже держит 26 сигналов — это предел SwiftSignalKit, туда добавлять нельзя.

```swift
            self.allAdMessagesPromise.get(),
            self.donutgramShadowBanPromise.get()
```

Разбор (L1970):

```swift
            let (historyAppearsCleared, pendingUnpinnedAllMessages, pendingRemovedMessages, currentlyPlayingMessageIdAndType, scrollToMessageId, chatHasBots, allAdMessages, shadowBanState) = promises
```

Вызов функции записей (L2244): принять третье значение и передать состояние только в режиме пузырей. Вкладки
«Файлы», «Ссылки» и «Голосовые» в профиле идут в режиме `.list` и не фильтруются.

```swift
                let (filteredEntries, updatedChatHistoryEntriesForViewState, donutgramHiddenCount) = chatHistoryEntriesForView(
```
```swift
                    pendingRemovedMessages: pendingRemovedMessages,
                    shadowBan: mode == .bubbles ? shadowBanState : nil,
```

Создание вида (L2274): дописать последний аргумент.

```swift
                let processedView = ChatHistoryView(originalView: view, filteredEntries: filteredEntries, associatedData: associatedData, lastHeaderId: lastHeaderId, id: id, locationInput: update.2, ignoreMessagesInTimestampRange: update.3, ignoreMessageIds: update.4, donutgramHiddenCount: donutgramHiddenCount)
```

- [ ] **Шаг 3: наблюдатель смены бана**

В `init` сразу после блока `self.donutgramSettingsObserver = …` (заканчивается `})` около L1309) добавить:

```swift
        // The shadow ban list or «Показать скрытые» changed: rebuild the entries, then the reply headers of loaded messages.
        self.donutgramShadowBanObserver = NotificationCenter.default.addObserver(forName: DGSimpleSettings.shadowBanDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.donutgramShadowBanPromise.set(DonutgramShadowBan.State.current)
            self.updateLoadedMessageItems(includeAllMessages: true)
        })
```

В `deinit` после снятия `donutgramSettingsObserver` добавить:

```swift
        if let donutgramShadowBanObserver = self.donutgramShadowBanObserver {
            NotificationCenter.default.removeObserver(donutgramShadowBanObserver)
        }
```

Смена только фильтра даёт `.InteractiveChanges` (L2302–2304): `originalView.entries` не изменились, `scrollPosition`
обнуляется. Поэтому записи уезжают анимацией, без прыжка скролла. Ничего добавлять не нужно.

- [ ] **Шаг 4: якорь подгрузки по краям реального окна**

В `processDisplayedItemRangeChanged`, сразу после строки
`if let loaded = displayedRange.visibleRange, let firstEntry = historyView.filteredEntries.first, let lastEntry = historyView.filteredEntries.last {`
(L3458), добавить:

```swift
            // Shadow-banned messages are not entries: anchor on the window's real edges, or loading stalls behind 22+ of them.
            var earlierAnchorIndex = firstEntry.index
            var laterAnchorIndex = lastEntry.index
            if historyView.donutgramHiddenCount > 0 {
                earlierAnchorIndex = historyView.originalView.entries.first?.index ?? earlierAnchorIndex
                laterAnchorIndex = historyView.originalView.entries.last?.index ?? laterAnchorIndex
            }
```

В этом же блоке заменить:
- `.Navigation(index: .message(lastEntry.index), anchorIndex: .message(lastEntry.index), …` (L3500) на
  `.Navigation(index: .message(laterAnchorIndex), anchorIndex: .message(laterAnchorIndex), …`;
- `.Navigation(index: .message(firstEntry.index), anchorIndex: .message(firstEntry.index), …` (L3509) на
  `.Navigation(index: .message(earlierAnchorIndex), anchorIndex: .message(earlierAnchorIndex), …`.

Больше `firstEntry` и `lastEntry` в блоке не используются как якоря. Проверить по `grep`, что предупреждений о
неиспользуемых переменных не будет: обе по-прежнему читаются в инициализации якорей.

- [ ] **Шаг 5: окно, где скрыто всё**

Добавить метод рядом с `updateMaxVisibleReadIncomingMessageIndex` (L3839):

```swift
    /// Every message of the loaded window is hidden by the shadow ban: load the next window instead of showing «no messages».
    /// Returns false when nothing is left to load, so the chat really has no visible messages.
    private func donutgramLoadPastHiddenWindow(_ historyView: ChatHistoryView) -> Bool {
        let originalView = historyView.originalView
        guard let firstEntry = originalView.entries.first, let lastEntry = originalView.entries.last else {
            return false
        }
        let canLoadEarlier = originalView.earlierId != nil || originalView.holeEarlier
        let canLoadLater = originalView.laterId != nil || originalView.holeLater
        guard let direction = self.donutgramHiddenWindowWalk.next(canLoadEarlier: canLoadEarlier, canLoadLater: canLoadLater) else {
            return false
        }
        let anchorIndex = direction == .earlier ? firstEntry.index : lastEntry.index
        let locationInput: ChatHistoryLocation = .Navigation(index: .message(anchorIndex), anchorIndex: .message(anchorIndex), count: historyMessageCount, highlight: false)
        if self.chatHistoryLocationValue?.content != locationInput {
            self.chatHistoryLocationValue = ChatHistoryLocationInput(content: locationInput, id: self.takeNextHistoryLocationId())
        }
        return true
    }
```

В обработчике перехода сразу после `strongSelf.historyView = transition.historyView` (L4202) сбрасывать обход:

```swift
                if !transition.historyView.filteredEntries.isEmpty {
                    strongSelf.donutgramHiddenWindowWalk = DonutgramShadowBan.HiddenWindowWalk()
                }
```

Там же, в ветке `if historyView.filteredEntries.isEmpty {` (L4215), между `if historyView.originalView.isLoading {…}`
и `else if let firstEntry = historyView.originalView.entries.first {` вставить ветку:

```swift
                        } else if historyView.donutgramHiddenCount > 0, strongSelf.donutgramLoadPastHiddenWindow(historyView) {
                            loadState = .loading(false)
```

Получится цепочка `if isLoading {…} else if donutgramHiddenCount > 0, … {…} else if let firstEntry … {…} else {…}`.

- [ ] **Шаг 6: прочтение скрытых после последнего видимого**

Добавить метод рядом с методом из шага 5:

```swift
    /// Shadow-banned messages after the newest read one, up to the next visible message, are never on screen: count them as
    /// read, or the chat keeps an unread badge for them.
    private func donutgramReadIndexPastHiddenMessages(_ index: MessageIndex) -> MessageIndex {
        guard let historyView = (self.listView.opaqueTransactionState as? ChatHistoryTransactionOpaqueState)?.historyView, historyView.donutgramHiddenCount > 0 else {
            return index
        }
        var visibleIndices: [MessageIndex] = []
        for entry in historyView.filteredEntries {
            switch entry {
            case let .MessageEntry(message, _, _, _, _, _):
                if message.adAttribute == nil {
                    visibleIndices.append(message.index)
                }
            case let .MessageGroupEntry(_, messages, _):
                visibleIndices.append(contentsOf: messages.map { $0.0.index })
            default:
                break
            }
        }
        visibleIndices.sort()
        return DonutgramShadowBan.readIndexPastHidden(index, visibleIndices: visibleIndices, windowIndices: historyView.originalView.entries.map(\.index))
    }
```

В `visibleContentOffsetChanged` (L1195–1197) заменить

```swift
                if let maxMessage {
                    strongSelf.updateMaxVisibleReadIncomingMessageIndex(maxMessage)
                }
```

на

```swift
                if let maxMessage {
                    strongSelf.updateMaxVisibleReadIncomingMessageIndex(strongSelf.donutgramReadIndexPastHiddenMessages(maxMessage))
                }
```

- [ ] **Шаг 7: скрытое сообщение пришло без изменения списка**

`ListView.transaction` при пустых изменениях не вызывает ни `visibleContentOffsetChanged`, ни
`displayedItemRangeChanged`. В обработчике перехода сразу после блока
`if strongSelf.loadState != loadState { … }` (заканчивается около L4287) добавить:

```swift
                if transition.historyView.donutgramHiddenCount > 0 && !transition.historyView.filteredEntries.isEmpty {
                    // A hidden message can arrive without changing the list, and then no scroll callback reads it:
                    // at the bottom of the chat everything up to the newest message is read.
                    if strongSelf.isScrollAtBottomPosition && transition.historyView.originalView.laterId == nil && !transition.historyView.originalView.holeLater, let lastIndex = transition.historyView.originalView.entries.last?.index {
                        strongSelf.updateMaxVisibleReadIncomingMessageIndex(lastIndex)
                    }
                    // The displayed-range pass then consumes its unseen mention.
                    Queue.mainQueue().justDispatch { [weak self] in
                        self?.listView.updateVisibleItemRange(force: true)
                    }
                }
```

Чтение идёт через `updateMaxVisibleReadIncomingMessageIndex`, затем `readHistory` (L2551), затем
`applyMaxReadIndex` с проверкой `canReadHistory` и режима призрака в TelegramCore.

- [ ] **Шаг 8: скрытые упоминания**

После `maxMessageIndexForEntries` (заканчивается L198) добавить файловую функцию:

```swift
/// Unseen mentions in shadow-banned messages between the neighbours of the visible range: they're never on screen, so they're
/// consumed when their place is, like visible ones, and, like them, not while their content is unconsumed.
private func donutgramHiddenUnseenMentions(_ view: ChatHistoryView, indexRange: (Int, Int)) -> [MessageId] {
    var lowerBound: MessageIndex?
    if indexRange.0 > 0 && indexRange.0 <= view.filteredEntries.count {
        lowerBound = view.filteredEntries[indexRange.0 - 1].index
    }
    var upperBound: MessageIndex?
    if indexRange.1 >= 0 && indexRange.1 + 1 < view.filteredEntries.count {
        upperBound = view.filteredEntries[indexRange.1 + 1].index
    }
    var result: [MessageId] = []
    for entry in view.originalView.entries {
        if let lowerBound, entry.index <= lowerBound {
            continue
        }
        if let upperBound, entry.index >= upperBound {
            break
        }
        let message = entry.message
        if !message.tags.contains(.unseenPersonalMessage) || !DonutgramShadowBan.isHidden(message) {
            continue
        }
        var hasMention = false
        var hasUnconsumedContent = false
        for attribute in message.attributes {
            if let attribute = attribute as? ConsumablePersonalMentionMessageAttribute, !attribute.pending {
                hasMention = true
            } else if let attribute = attribute as? ConsumableContentMessageAttribute, !attribute.consumed {
                hasUnconsumedContent = true
            }
        }
        if hasMention && !hasUnconsumedContent {
            result.append(message.id)
        }
    }
    return result
}
```

В `processDisplayedItemRangeChanged` сразу перед `if !messageIdsWithViewCount.isEmpty {` (L3297) добавить:

```swift
            if historyView.donutgramHiddenCount > 0 {
                messageIdsWithUnseenPersonalMention.append(contentsOf: donutgramHiddenUnseenMentions(historyView, indexRange: indexRange))
            }
```

`indexRange` объявлен в начале той же ветки `if let visible = displayedRange.visibleRange {` (L2897).

- [ ] **Шаг 9: полупрозрачность показанных скрытых**

В `ChatMessageItemView.setupItem(_:synchronousLoad:)` заменить строку с `self.alpha`:

```swift
        let isRevealedShadowBanned = DGSimpleSettings.shared.isShadowBanRevealed(chatPeerId: item.message.id.peerId.toInt64()) && item.content.contains(where: { element in
            DonutgramShadowBan.isBannedContent(element.0)
        })
        self.alpha = (isDeleted && DGSimpleSettings.shared.semiTransparentDeletedMessages) || isRevealedShadowBanned ? 0.55 : 1.0
```

- [ ] **Шаг 10: сверка и контрольная точка**

```bash
grep -n "chatHistoryEntriesForView(" -r submodules/TelegramUI/Sources
```
Ожидается: одно определение и один вызов (L2244).
```bash
grep -n "ChatHistoryView(originalView" submodules/TelegramUI/Sources/ChatHistoryListNode.swift
```
Ожидается: два места. L2053 без нового аргумента — в нём срабатывает значение по умолчанию.
```bash
git diff --check
```
Ожидается: пусто.

Сценарий для фокуса проверки №4: на телефоне при открытой группе забанить автора из профиля. Его сообщения
уезжают, лента не прыгает. «Показать скрытые» возвращает их полупрозрачными.

---

### Task 3: список чатов — превью, перерисовка, «печатает…» (коммит 3)

**Файлы:**
- Изменить: `submodules/ChatListUI/Sources/Node/ChatListItem.swift` (L2486–2492)
- Изменить: `submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift` (L934)
- Изменить: `submodules/ChatListUI/Sources/Node/ChatListNode.swift` (свойство, конец `init` около L3190, `deinit`
  L3193, фильтр активностей L2759–2769)

**Интерфейсы:** берёт `DonutgramShadowBan.isHidden(_: EngineMessage)`, `isPeerHidden(_:inChat:state:)`,
`DGSimpleSettings.shadowBanDidChangeNotification`.

- [ ] **Шаг 1: превью строки**

В `ChatListItem` сразу после блока `if let messageValue = messages.last { … .historyCleared … }` (L2486–2492)
добавить:

```swift
            // A shadow-banned last message leaves the preview empty, as cleared history does; the row keeps its date and
            // its tap, which still opens the chat or topic through peerData.messages.
            if let messageValue = messages.last, DonutgramShadowBan.isHidden(messageValue) {
                messages = []
            }
```

Чистить нужно именно здесь, в раскладке строки, а не в `ChatListNodeEntries`. Тап (L625–658) берёт
`peerData.messages.last`, и с пустым списком строка темы форума открывала бы группу без темы.

- [ ] **Шаг 2: строка «Архив»**

В `ChatListNodeEntries.swift` в `GroupReferenceEntryData(...)` заменить `message: groupReference.topMessage,` на:

```swift
                    message: groupReference.topMessage.flatMap { DonutgramShadowBan.isHidden($0) ? nil : $0 },
```

Без сообщения строка «Архив» показывает список архивных чатов (`contentPeer = .group(peers)` в `ChatListItem`).
Тап по «Архиву» не зависит от сообщения: это `groupSelected`.

- [ ] **Шаг 3: перерисовка всех строк при смене бана**

В `ChatListNode` рядом с `private var activityStatusesDisposable: Disposable?` (L1324) добавить:

```swift
    private var donutgramShadowBanObserver: NSObjectProtocol?
```

В конце `init`, сразу после `self.view.addGestureRecognizer(selectionRecognizer)` (около L3190), добавить:

```swift
        // Previews and typing read the shadow ban at layout time: a fresh presentation data object lays out every row again,
        // as a theme change does.
        self.donutgramShadowBanObserver = NotificationCenter.default.addObserver(forName: DGSimpleSettings.shadowBanDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.updateState { state in
                var state = state
                let current = state.presentationData
                state.presentationData = ChatListPresentationData(theme: current.theme, fontSize: current.fontSize, strings: current.strings, dateTimeFormat: current.dateTimeFormat, nameSortOrder: current.nameSortOrder, nameDisplayOrder: current.nameDisplayOrder, disableAnimations: current.disableAnimations)
                return state
            }
        })
```

В `deinit` добавить:

```swift
        if let donutgramShadowBanObserver = self.donutgramShadowBanObserver {
            NotificationCenter.default.removeObserver(donutgramShadowBanObserver)
        }
```

Если в `ChatListNode.swift` нет `import DGSimpleSettings`, добавить его в блок импортов: зависимость есть в
`submodules/ChatListUI/BUILD`.

- [ ] **Шаг 4: «печатает…» в списке чатов**

В подписке `context.account.allPeerInputActivities()` (L2756) заменить замыкание `removeAll(where:)`:

```swift
            for key in activitiesByPeerId.keys {
                activitiesByPeerId[key]?.removeAll(where: { peerId, activity in
                    if DonutgramShadowBan.isPeerHidden(peerId, inChat: key.peerId) {
                        return true
                    }
                    switch activity {
                    case .interactingWithEmoji:
                        return true
                    case .speakingInGroupCall:
                        return true
                    default:
                        return false
                    }
                })
            }
```

- [ ] **Шаг 5: контрольная точка и фокус проверки №3**

```bash
git diff --check
```
Ожидается: пусто.

На телефоне: в форуме, где последнее сообщение темы от забаненного, превью темы пустое, а тап открывает эту тему.
Строка «Архив» с таким сообщением показывает список чатов.

---

### Task 4: цитаты в ответах (коммит 3)

**Файлы** (вставка сразу после цикла `for attribute in …`, в котором есть ветка `ReplyMessageAttribute`):
- `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift` — перед
  `if firstMessage.isRestricted(platform: "ios", …` (L2181)
- `submodules/TelegramUI/Components/Chat/ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift` —
  после цикла, который кончается на `replyMarkup = attribute` + `}` + `}` (около L1258–1261)
- `submodules/TelegramUI/Components/Chat/ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift` — после
  цикла около L738–752
- `submodules/TelegramUI/Components/Chat/ChatMessageInstantVideoItemNode/Sources/ChatMessageInstantVideoItemNode.swift` —
  перед `if replyMessage != nil || replyForward != nil || replyStory != nil {` (около L521)
- `submodules/TelegramUI/Components/Chat/ChatMessageInteractiveInstantVideoNode/Sources/ChatMessageInteractiveInstantVideoNode.swift` —
  перед `if replyMessage != nil || replyForward != nil || replyStory != nil {` (около L408)

**Интерфейсы:** берёт `DonutgramShadowBan.hidesReplyHeader(in: Message) -> Bool`.

- [ ] **Шаг 1: пузырь**

Перед `if firstMessage.isRestricted(platform: "ios", …` вставить:

```swift
        // A reply to a shadow-banned message loses its header: the quote would show the hidden message.
        if DonutgramShadowBan.hidesReplyHeader(in: firstMessage) {
            replyMessage = nil
            replyQuote = nil
            replyForward = nil
            replyInnerSubject = nil
        }
```

- [ ] **Шаг 2: стикер, анимированный стикер и два узла кружка**

В каждом из четырёх файлов в указанном месте вставить такой же блок с `item.message`:

```swift
            // A reply to a shadow-banned message loses its header: the quote would show the hidden message.
            if DonutgramShadowBan.hidesReplyHeader(in: item.message) {
                replyMessage = nil
                replyQuote = nil
                replyForward = nil
                replyInnerSubject = nil
            }
```

Перед вставкой проверить объявления: `grep -n "var replyInnerSubject\|var replyQuote\|var replyForward\|var replyMessage" <файл>`.
Обнулять только объявленные в этой функции переменные. Если `replyInnerSubject` в файле нет, строку убрать. Отступ
должен совпадать с соседним кодом.

- [ ] **Шаг 3: контрольная точка**

```bash
git diff --check
```
```bash
grep -rn "hidesReplyHeader" submodules/TelegramUI/Components/Chat
```
Ожидается: `git diff --check` пуст, `grep` находит ровно пять вызовов.

---

### Task 5: уведомления, поиск и закреп (коммит 3)

**Файлы:**
- `submodules/TelegramUI/Sources/ApplicationContext.swift` (L306–315)
- `submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift` (L3398–3411, L3422–3435)
- `submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift` (L95, L150)
- `submodules/TelegramUI/Sources/ChatControllerNode.swift` (L3460)
- `submodules/TelegramUI/Sources/ChatSearchResultsContollerNode.swift` (L342)
- `submodules/TelegramUI/Sources/ChatController.swift` (L7486–7491)

**Интерфейсы:** берёт `DonutgramShadowBan.isHidden(_:)`, `isHidden(_:state:)`, `filteringHidden(_: SearchMessagesResult)`,
`stateSignal()`.

- [ ] **Шаг 1: баннер внутри приложения**

В `messageList.filter { item in` после `guard let message = item.0.first else { return false }` добавить:

```swift
                    if DonutgramShadowBan.isHidden(message) {
                        return false
                    }
```

Фильтр стоит до звука, вибрации (L376–393) и баннера (L422).

- [ ] **Шаг 2: глобальный поиск**

В цикле публичных постов `for message in foundPublicMessageSet.messages {` после проверки `existingPostIds` и в цикле
сообщений `for message in foundRemoteMessageSet.messages {` после проверки `existingMessageIds` добавить:

```swift
                            if DonutgramShadowBan.isHidden(message) {
                                continue
                            }
```

Отступ — как у соседнего `continue`.

- [ ] **Шаг 3: поиск в чате (четыре вызова)**

В `ChatControllerUpdateSearch.swift` (L95) сигнал поиска:

```swift
                        let search = self.context.engine.messages.searchMessages(location: searchState.location, query: searchState.query, state: nil, limit: limit)
                        |> map { result, state -> (SearchMessagesResult, SearchMessagesState) in
                            return (DonutgramShadowBan.filteringHidden(result), state)
                        }
                        |> delay(0.2, queue: Queue.mainQueue())
```

Там же догрузка (L150):

```swift
                        searchDisposable.set((self.context.engine.messages.searchMessages(location: searchState.location, query: searchState.query, state: loadMoreState, limit: limit)
                        |> map { result, state -> (SearchMessagesResult, SearchMessagesState) in
                            return (DonutgramShadowBan.filteringHidden(result), state)
                        }
                        |> delay(0.2, queue: Queue.mainQueue())
```

`ChatControllerNode.swift` (L3460):

```swift
                            self.loadMoreSearchResultsDisposable = (self.context.engine.messages.searchMessages(location: currentSearchState.location, query: currentSearchState.query, state: currentResultsState.state)
                            |> map { result, state -> (SearchMessagesResult, SearchMessagesState) in
                                return (DonutgramShadowBan.filteringHidden(result), state)
                            }
                            |> deliverOnMainQueue).startStrict(next: { [weak self] results, updatedState in
```

`ChatSearchResultsContollerNode.swift` (L342):

```swift
        self.loadMoreDisposable.set((self.context.engine.messages.searchMessages(location: self.location, query: self.searchQuery, state: self.searchState)
        |> map { result, state -> (SearchMessagesResult, SearchMessagesState) in
            return (DonutgramShadowBan.filteringHidden(result), state)
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] (updatedResult, updatedState) in
```

Не трогать:
- `ChatControllerAdminBanUsers.swift` (L162) — счётчик «удалить все сообщения пользователя» для админа;
- `ChatControllerNode.swift` (L3239) — поиск по тегу реакции в «Избранном».

- [ ] **Шаг 4: закреп**

В `ChatController.swift` (L7486) добавить состояние бана в `combineLatest` и фильтровать в начале `map`:

```swift
            topPinnedMessage = combineLatest(queue: .mainQueue(),
                adjustedReplyHistory,
                topMessage,
                referenceMessage ?? .single(nil),
                DonutgramShadowBan.stateSignal()
            )
            |> map { pinnedMessages, topMessage, referenceMessage, shadowBanState -> ChatPinnedMessage? in
                // Shadow-banned pins leave the bar, and the «N of M» count follows the visible ones.
                var pinnedMessages = pinnedMessages
                var topMessage = topMessage
                if !shadowBanState.bannedPeerIds.isEmpty {
                    var visibleMessages: [PinnedHistory.PinnedMessage] = []
                    var hiddenBefore = 0
                    for pinnedMessage in pinnedMessages.messages {
                        if DonutgramShadowBan.isHidden(pinnedMessage.message, state: shadowBanState) {
                            hiddenBefore += 1
                        } else {
                            visibleMessages.append(PinnedHistory.PinnedMessage(message: pinnedMessage.message, index: pinnedMessage.index - hiddenBefore))
                        }
                    }
                    pinnedMessages = PinnedHistory(messages: visibleMessages, totalCount: max(0, pinnedMessages.totalCount - hiddenBefore))
                    if let topMessageValue = topMessage, DonutgramShadowBan.isHidden(topMessageValue.message, state: shadowBanState) {
                        topMessage = nil
                    }
                }

                var message: ChatPinnedMessage?
```

Остальное тело `map` не меняется. Если `topMessage` обнулён, ниже срабатывает
`topMessage?.message.id ?? pinnedMessages.messages[pinnedMessages.messages.count - 1].message.id`.

- [ ] **Шаг 5: контрольная точка**

```bash
git diff --check
```
```bash
grep -rn "filteringHidden(result)" submodules/TelegramUI/Sources
```
Ожидается: `git diff --check` пуст, `grep` находит четыре вызова.

---

### Task 6: «печатает…» в чате, реакции, аватарки под постом и сторис (коммит 4)

**Файлы:**
- `submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` (L5155)
- `submodules/TelegramUI/Components/Chat/ChatMessageReactionsFooterContentNode/Sources/ChatMessageReactionsFooterContentNode.swift` (L187–193)
- `submodules/Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift` (L772–794, L889, L920)
- `submodules/TelegramUI/Components/Chat/ChatMessageCommentFooterContentNode/Sources/ChatMessageCommentFooterContentNode.swift` (L133–135)
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift` (L1017)

**Интерфейсы:** берёт `DonutgramShadowBan.isPeerHidden(_:inChat:state:)`, `stateSignal()`,
`filteringHidden(_: EngineStorySubscriptions, state:)`.

- [ ] **Шаг 1: «печатает…» в шапке чата**

Между `self.context.account.peerInputActivities(peerId: activitySpace)` и `|> mapToSignal { activities -> …` вставить
отдельный `map`, чтобы не переименовывать переменные внутри:

```swift
                    self.peerInputActivitiesDisposable = (self.context.account.peerInputActivities(peerId: activitySpace)
                    |> map { activities -> [(PeerId, PeerInputActivity)] in
                        return activities.filter { !DonutgramShadowBan.isPeerHidden($0.0, inChat: activitySpace.peerId) }
                    }
                    |> mapToSignal { activities -> Signal<[(EnginePeer, PeerInputActivity)], NoError> in
```

- [ ] **Шаг 2: аватарки на кнопках реакций**

В ветке групп (`for recentPeer in reactions.recentPeers {`) заменить условие добавления:

```swift
                    for recentPeer in reactions.recentPeers {
                        if recentPeer.value == reaction.value {
                            if let peer = message.peers[recentPeer.peerId], !DonutgramShadowBan.isPeerHidden(recentPeer.peerId, inChat: message.id.peerId) {
                                peers.append(EnginePeer(peer))
                            }
                        }
                    }
```

Если аватарок становится меньше, чем реакций (`peers.count != Int(reaction.count)`), следующая строка очищает список,
и кнопка показывает цифру.

- [ ] **Шаг 3: список «кто поставил / просмотрел»**

В `private struct ItemsState` добавить поле и параметр. Фильтровать после слияния со статистикой прочтений:

```swift
        private struct ItemsState {
            let listState: EngineMessageReactionListContext.State
            let readStats: MessageReadStats?
            let chatPeerId: EnginePeer.Id

            let mergedItems: [EngineMessageReactionListContext.Item]

            init(listState: EngineMessageReactionListContext.State, readStats: MessageReadStats?, chatPeerId: EnginePeer.Id) {
                self.listState = listState
                self.readStats = readStats
                self.chatPeerId = chatPeerId

                var mergedItems: [EngineMessageReactionListContext.Item] = listState.items
                if !listState.canLoadMore, let readStats = readStats {
                    var existingPeers = Set(mergedItems.map(\.peer.id))
                    for peer in readStats.peers {
                        if !existingPeers.contains(peer.id) {
                            existingPeers.insert(peer.id)
                            mergedItems.append(EngineMessageReactionListContext.Item(peer: peer, reaction: nil, timestamp: readStats.readTimestamps[peer.id], timestampIsReaction: false))
                        }
                    }
                }
                // Shadow-banned people leave the list; the tab counts stay as the server gives them.
                mergedItems.removeAll(where: { DonutgramShadowBan.isPeerHidden($0.peer.id, inChat: chatPeerId) })

                self.mergedItems = mergedItems
            }
```

Оба вызова:
- L889: `ItemsState(listState: EngineMessageReactionListContext.State(message: message, readStats: readStats, reaction: reaction), readStats: readStats, chatPeerId: message.id.peerId)`
- L920: `ItemsState(listState: state, readStats: strongSelf.state.readStats, chatPeerId: strongSelf.state.chatPeerId)`

Проверить, что других вызовов нет: `grep -n "ItemsState(" …/ReactionListContextMenuContent.swift` находит два места,
плюс объявление.

- [ ] **Шаг 4: аватарки под постом канала**

```swift
                        replyPeers = attribute.latestUsers.compactMap { peerId -> EnginePeer? in
                            if DonutgramShadowBan.isPeerHidden(peerId, inChat: item.message.id.peerId) {
                                return nil
                            }
                            return item.message.peers[peerId].flatMap(EnginePeer.init)
                        }
```

- [ ] **Шаг 5: сторис**

В `TelegramEngineMessages.swift` переименовать существующую функцию, не меняя тело. Строку
`public func storySubscriptions(isHidden: Bool, tempKeepNewlyArchived: Bool = false) -> Signal<EngineStorySubscriptions, NoError> {`
заменить на:

```swift
        public func storySubscriptions(isHidden: Bool, tempKeepNewlyArchived: Bool = false) -> Signal<EngineStorySubscriptions, NoError> {
            // Shadow-banned peers leave the story strip, the archive strip and the viewer's peer sequence.
            return combineLatest(
                self.donutgramUnfilteredStorySubscriptions(isHidden: isHidden, tempKeepNewlyArchived: tempKeepNewlyArchived),
                DonutgramShadowBan.stateSignal()
            )
            |> map { subscriptions, state -> EngineStorySubscriptions in
                return DonutgramShadowBan.filteringHidden(subscriptions, state: state)
            }
            |> distinctUntilChanged
        }

        private func donutgramUnfilteredStorySubscriptions(isHidden: Bool, tempKeepNewlyArchived: Bool) -> Signal<EngineStorySubscriptions, NoError> {
```

Старое тело (`return \`deferred\` { … }`) остаётся телом `donutgramUnfilteredStorySubscriptions`.

- [ ] **Шаг 6: контрольная точка**

```bash
git diff --check
```
```bash
grep -rn "func storySubscriptions(isHidden" submodules/TelegramCore/Sources
```
Ожидается: `git diff --check` пуст, `grep` находит одно определение — публичную обёртку.

---

### Task 7: страница «Теневой бан» и помощник тоста (коммит 5)

**Файлы:**
- Создать: `Donutgram/DGSettingsUI/Sources/DGShadowBanController.swift`
- Изменить: `Donutgram/DGSettingsUI/BUILD` — зависимости
- Изменить: `Donutgram/DGSettingsUI/Sources/DGSettingLinks.swift` — `enum DGSettingsPage`
- Изменить: `Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift` — `dgSpySettingsController`,
  `dgSettingsControllerForLink`
- Изменить: `Donutgram/DGSettingsUI/Sources/DGSettingsController.swift` — `dgSettingsSymbol`

**Интерфейсы:**
- Берёт: `DGSimpleSettings` (задача 1), `DonutgramShadowBan.stateSignal()`, `canBan(_:accountPeerId:)`.
- Даёт задаче 8:
  - `public func dgToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void)`;
  - `public func dgShadowBanController(context: AccountContext, focusKey: String? = nil) -> ViewController`.

- [ ] **Шаг 1: зависимости**

В `Donutgram/DGSettingsUI/BUILD` в `deps` после `"//submodules/UndoUI:UndoUI",` добавить:

```
        "//submodules/ItemListPeerItem:ItemListPeerItem",
        "//submodules/ItemListPeerActionItem:ItemListPeerActionItem",
```

- [ ] **Шаг 2: экран и помощник**

Создать `Donutgram/DGSettingsUI/Sources/DGShadowBanController.swift`:

```swift
import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import ItemListPeerActionItem
import LocalizedPeerData
import UndoUI
import DGSimpleSettings

/// Bans or unbans `peer` and shows «<name> в теневом бане» or «<name> убран из теневого бана» with «Отменить».
public func dgToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void) {
    let settings = DGSimpleSettings.shared
    let peerId = peer.id.toInt64()
    let ban = !settings.isShadowBanned(peerId)
    settings.setShadowBanned(ban, peerId: peerId)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let name = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
    let text = ban ? "\(name) в теневом бане" : "\(name) убран из теневого бана"
    present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: "Отменить"), elevatedLayout: false, action: { action in
        if case .undo = action {
            settings.setShadowBanned(!ban, peerId: peerId)
        }
        return false
    }))
}

private final class DGShadowBanArguments {
    let context: AccountContext
    let setPeerIdWithRevealedOptions: (EnginePeer.Id?, EnginePeer.Id?) -> Void
    let addPeer: () -> Void
    let removePeer: (EnginePeer.Id) -> Void
    let openPeer: (EnginePeer) -> Void

    init(context: AccountContext, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void, addPeer: @escaping () -> Void, removePeer: @escaping (EnginePeer.Id) -> Void, openPeer: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.addPeer = addPeer
        self.removePeer = removePeer
        self.openPeer = openPeer
    }
}

private enum DGShadowBanSection: Int32 {
    case peers
}

private enum DGShadowBanEntryId: Hashable {
    case add
    case peer(EnginePeer.Id)
    case info
}

private enum DGShadowBanEntry: ItemListNodeEntry {
    case add(PresentationTheme)
    // The peer, its subtitle and whether it is known to this account (an unknown one can't be opened).
    case peer(Int32, EnginePeer, String, Bool, ItemListPeerItemEditing)
    case info(String)

    var section: ItemListSectionId {
        return DGShadowBanSection.peers.rawValue
    }

    var stableId: DGShadowBanEntryId {
        switch self {
        case .add:
            return .add
        case let .peer(_, peer, _, _, _):
            return .peer(peer.id)
        case .info:
            return .info
        }
    }

    private var sortIndex: Int32 {
        switch self {
        case .add:
            return 0
        case let .peer(index, _, _, _, _):
            return 1 + index
        case .info:
            return Int32.max
        }
    }

    static func ==(lhs: DGShadowBanEntry, rhs: DGShadowBanEntry) -> Bool {
        switch lhs {
        case let .add(lhsTheme):
            if case let .add(rhsTheme) = rhs, lhsTheme === rhsTheme {
                return true
            }
            return false
        case let .peer(lhsIndex, lhsPeer, lhsText, lhsKnown, lhsEditing):
            if case let .peer(rhsIndex, rhsPeer, rhsText, rhsKnown, rhsEditing) = rhs, lhsIndex == rhsIndex, lhsPeer == rhsPeer, lhsText == rhsText, lhsKnown == rhsKnown, lhsEditing == rhsEditing {
                return true
            }
            return false
        case let .info(lhsText):
            if case let .info(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: DGShadowBanEntry, rhs: DGShadowBanEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DGShadowBanArguments
        switch self {
        case let .add(theme):
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesItemList.addPersonIcon(theme), title: "Добавить", sectionId: self.section, height: .generic, editing: false, action: {
                arguments.addPeer()
            })
        case let .peer(_, peer, text, isKnown, editing):
            let revealOptions = ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: "Убрать", action: {
                arguments.removePeer(peer.id)
            })])
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .text(text, .secondary), label: .none, editing: editing, revealOptions: revealOptions, switchValue: nil, enabled: true, selectable: isKnown, sectionId: self.section, action: {
                arguments.openPeer(peer)
            }, setPeerIdWithRevealedOptions: { previousId, id in
                arguments.setPeerIdWithRevealedOptions(previousId, id)
            }, removePeer: { peerId in
                arguments.removePeer(peerId)
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct DGShadowBanState: Equatable {
    var editing = false
    var peerIdWithRevealedOptions: EnginePeer.Id?
}

// A row for an id this account doesn't know (e.g. banned from another account): it can still be removed.
private func dgUnknownShadowBanPeer(_ peerId: EnginePeer.Id) -> EnginePeer {
    return .user(TelegramUser(id: peerId, accessHash: nil, firstName: "Неизвестный", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}

private func dgShadowBanSubtitle(_ peer: EnginePeer?, peerId: EnginePeer.Id) -> String {
    guard let peer else {
        return "ID \(peerId.id._internalGetInt64Value())"
    }
    if let username = peer.addressName {
        return "@\(username)"
    }
    switch peer {
    case let .user(user):
        return user.botInfo != nil ? "бот" : "пользователь"
    case .channel:
        return "канал"
    default:
        return ""
    }
}

/// «Теневой бан» in «Основные»: the banned people, bots and channels, adding and removing them.
public func dgShadowBanController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let statePromise = ValuePromise(DGShadowBanState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DGShadowBanState())
    let updateState: ((DGShadowBanState) -> DGShadowBanState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = DGShadowBanArguments(context: context, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            var state = state
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                state.peerIdWithRevealedOptions = peerId
            }
            return state
        }
    }, addPeer: {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeGroups, .excludeSecretChats, .excludeSavedMessages, .removeSearchHeader, .excludeRecent, .doNotSearchMessages], title: "Теневой бан"))
        controller.peerSelected = { [weak controller] peer, _ in
            if DonutgramShadowBan.canBan(peer, accountPeerId: context.account.peerId) {
                DGSimpleSettings.shared.setShadowBanned(true, peerId: peer.id.toInt64())
            }
            controller?.dismiss()
        }
        pushControllerImpl?(controller)
    }, removePeer: { peerId in
        DGSimpleSettings.shared.setShadowBanned(false, peerId: peerId.toInt64())
    }, openPeer: { peer in
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            pushControllerImpl?(controller)
        }
    })

    let bannedPeers: Signal<([EnginePeer.Id], [EnginePeer.Id: EnginePeer]), NoError> = DonutgramShadowBan.stateSignal()
    |> map { state -> [EnginePeer.Id] in
        return state.bannedPeerIds.sorted().map { EnginePeer.Id($0) }
    }
    |> distinctUntilChanged
    |> mapToSignal { peerIds -> Signal<([EnginePeer.Id], [EnginePeer.Id: EnginePeer]), NoError> in
        return context.engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
        |> map { peerMap -> ([EnginePeer.Id], [EnginePeer.Id: EnginePeer]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (peerId, peer) in peerMap {
                if let peer {
                    peers[peerId] = peer
                }
            }
            return (peerIds, peers)
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), bannedPeers)
    |> deliverOnMainQueue
    |> map { presentationData, state, bannedPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (peerIds, peers) = bannedPeers
        var rightNavigationButton: ItemListNavigationButton?
        if !peerIds.isEmpty {
            if state.editing {
                rightNavigationButton = ItemListNavigationButton(content: .icon(.done), style: .bold, enabled: true, action: {
                    updateState { state in
                        var state = state
                        state.editing = false
                        return state
                    }
                })
            } else {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
                    updateState { state in
                        var state = state
                        state.editing = true
                        return state
                    }
                })
            }
        }

        // Peers known to this account first, by name; unknown ids after them.
        let orderedPeerIds = peerIds.sorted { lhs, rhs in
            switch (peers[lhs], peers[rhs]) {
            case let (lhsPeer?, rhsPeer?):
                return lhsPeer.compactDisplayTitle.localizedCaseInsensitiveCompare(rhsPeer.compactDisplayTitle) == .orderedAscending
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs < rhs
            }
        }

        var entries: [DGShadowBanEntry] = [.add(presentationData.theme)]
        for (index, peerId) in orderedPeerIds.enumerated() {
            let peer = peers[peerId]
            entries.append(.peer(Int32(index), peer ?? dgUnknownShadowBanPeer(peerId), dgShadowBanSubtitle(peer, peerId: peerId), peer != nil, ItemListPeerItemEditing(editable: true, editing: state.editing, revealed: peerId == state.peerIdWithRevealedOptions)))
        }
        entries.append(.info("Сообщения этих людей скрыты в группах, комментариях и каналах только на этом устройстве. Они об этом не узнают. Личные чаты не меняются."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Теневой бан"), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] pushed in
        (controller?.navigationController as? NavigationController)?.pushViewController(pushed)
    }
    return controller
}
```

`focusKey` нужен только для сигнатуры фабрики ссылок `(AccountContext, String?) -> ViewController`. Неиспользуемый
параметр функции предупреждения не даёт.

Сигнатуры, на которые опирается код, сверены на c7bb57884c:
- `PresentationResourcesItemList.addPersonIcon(_:)`;
- `EnginePeer.compactDisplayTitle` (LocalizedPeerData) и `EnginePeer.addressName`;
- `PeerSelectionController.peerSelected: ((EnginePeer, Int64?) -> Void)?`;
- `makePeerInfoController(…, peer: EnginePeer, …)`;
- `PeerId` с оператором `<`.

- [ ] **Шаг 3: ссылка на страницу**

В `enum DGSettingsPage` (`DGSettingLinks.swift`) после `case visualPhone = "visual-phone"` добавить:

```swift
    case shadowBan = "shadow-ban"
```

В `dgSettingsControllerForLink` после `case .visualPhone: makeController = dgVisualPhoneController` добавить:

```swift
    case .shadowBan: makeController = dgShadowBanController
```

- [ ] **Шаг 4: строка в «Основных»**

В `dgSpySettingsController` в `result` сразу после `.toggle(18, 1, "gifUnlock", "Обход блокировок GIF", s.gifUnlock, true)`
добавить строку:

```swift
.disclosure(19, 1, "shadowBan", "Теневой бан", s.shadowBannedPeerIds.isEmpty ? "Выключен" : "\(s.shadowBannedPeerIds.count)"),
```

Она стоит в том же массиве литералов, через запятую.

В `open: { key in switch key {` добавить:

```swift
        case "shadowBan": return dgShadowBanController(context: context)
```

Счётчик в строке обновляется при возврате со страницы: `needsRefreshOnAppear` в `dgController`.

В `dgSettingsSymbol` (`DGSettingsController.swift`) добавить:

```swift
    case "shadowBan": return "person.crop.circle.badge.xmark"
```

- [ ] **Шаг 5: контрольная точка**

```bash
git diff --check
```
```bash
grep -rn "shadowBan" Donutgram/DGSettingsUI/Sources
```
Ожидается: `git diff --check` пуст. `grep` находит четыре места: случай `enum`, фабрику ссылки, строку «Основных» с
`open` и символ.

---

### Task 8: меню сообщения и меню профиля (коммит 5)

**Файлы:**
- `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`:
  - пункт после блока «Пожаловаться/Заблокировать» (L1935–1949);
  - аватарки в шапке меню (L3760–3776);
  - импорт.
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift`:
  - блок перед `return .single(items)` в конце `mainItemsImpl` (L1267);
  - импорты.

**Интерфейсы:** берёт `dgToggleShadowBan(context:peer:present:)` (задача 7), `DonutgramShadowBan.banTarget(of:)`,
`canBan(_:accountPeerId:)`, `appliesToChat(_:chatPeer:)`, `appliesToChat(_ chatPeer: EnginePeer)`,
`isPeerHidden(_:inChat:state:)`, а также `DGSimpleSettings.hasShadowBans`, `isShadowBanned(_:)`,
`isShadowBanRevealed(chatPeerId:)` и `setShadowBanRevealed(_:chatPeerId:)`.

- [ ] **Шаг 1: пункт в меню сообщения**

В импорты `ChatInterfaceStateContextMenus.swift` рядом с `import DGSimpleSettings` добавить `import DGSettingsUI`.

Сразу после блока `if data.messageActions.options.contains(.report) { … } else if message.id.peerId.isReplies { … }`
добавить:

```swift
        // «Теневой бан» bans the sender of an incoming message in a group, channel or comments.
        if message.flags.contains(.Incoming), DonutgramShadowBan.appliesToChat(message.id.peerId, chatPeer: message.peers[message.id.peerId]), let target = DonutgramShadowBan.banTarget(of: message), target.id != message.id.peerId, DonutgramShadowBan.canBan(EnginePeer(target), accountPeerId: context.account.peerId) {
            let targetPeer = EnginePeer(target)
            let isBanned = DGSimpleSettings.shared.isShadowBanned(target.id.toInt64())
            actions.append(.action(ContextMenuActionItem(text: isBanned ? "Убрать из теневого бана" : "Теневой бан", icon: { theme in
                return generateTintedImage(image: UIImage(systemName: isBanned ? "eye" : "eye.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)), color: theme.actionSheet.primaryTextColor)
            }, action: { _, f in
                f(.dismissWithoutContent)
                dgToggleShadowBan(context: context, peer: targetPeer, present: { controller in
                    controllerInteraction.presentControllerInCurrent(controller, nil)
                })
            })))
        }
```

- [ ] **Шаг 2: аватарки в шапке меню сообщения**

В блоке `if let recentPeers = self.item.message.reactionsAttribute?.recentPeers, !recentPeers.isEmpty {` заменить условие:

```swift
                for recentPeer in recentPeers {
                    if let peer = self.item.message.peers[recentPeer.peerId], !DonutgramShadowBan.isPeerHidden(recentPeer.peerId, inChat: self.item.message.id.peerId) {
```

В ветке `else if let peers = self.currentStats?.peers {` заменить цикл:

```swift
            } else if let peers = self.currentStats?.peers {
                for peer in peers where !DonutgramShadowBan.isPeerHidden(peer.id, inChat: self.item.message.id.peerId) {
                    if !avatarsPeers.contains(where: { $0.id == peer.id }) {
                        avatarsPeers.append(peer)
                        if avatarsPeers.count == 3 {
                            break
                        }
                    }
                }
            }
```

- [ ] **Шаг 3: меню «…» профиля**

В импорты `PeerInfoScreenPerformButtonAction.swift` добавить `import DGSimpleSettings` и `import DGSettingsUI`.
Зависимости уже есть в `PeerInfoScreen/BUILD`.

Перед `return .single(items)` в конце `mainItemsImpl` (L1267, после ветки `.legacyGroup`) вставить:

```swift
                // Donutgram: «Теневой бан» for people, bots and channels, «Показать скрытые» for chats that hide messages.
                var shadowBanItems: [ContextMenuItem] = []
                if DonutgramShadowBan.canBan(peer, accountPeerId: strongSelf.context.account.peerId) {
                    let isBanned = DGSimpleSettings.shared.isShadowBanned(peer.id.toInt64())
                    shadowBanItems.append(.action(ContextMenuActionItem(text: isBanned ? "Убрать из теневого бана" : "Теневой бан", icon: { theme in
                        generateTintedImage(image: UIImage(systemName: isBanned ? "eye" : "eye.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)), color: theme.contextMenu.primaryColor)
                    }, action: { [weak self] _, f in
                        f(.dismissWithoutContent)
                        guard let self, let controller = self.controller else {
                            return
                        }
                        dgToggleShadowBan(context: self.context, peer: peer, present: { [weak controller] toast in
                            controller?.present(toast, in: .current)
                        })
                    })))
                }
                if DGSimpleSettings.shared.hasShadowBans && DonutgramShadowBan.appliesToChat(peer) {
                    let isRevealed = DGSimpleSettings.shared.isShadowBanRevealed(chatPeerId: peer.id.toInt64())
                    shadowBanItems.append(.action(ContextMenuActionItem(text: isRevealed ? "Спрятать скрытые сообщения" : "Показать скрытые сообщения", icon: { theme in
                        generateTintedImage(image: UIImage(systemName: isRevealed ? "eye.slash" : "eye", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)), color: theme.contextMenu.primaryColor)
                    }, action: { _, f in
                        f(.dismissWithoutContent)
                        DGSimpleSettings.shared.setShadowBanRevealed(!isRevealed, chatPeerId: peer.id.toInt64())
                    })))
                }
                if !shadowBanItems.isEmpty {
                    if !items.isEmpty {
                        items.append(.separator)
                    }
                    items.append(contentsOf: shadowBanItems)
                }

```

Проверить имена: `strongSelf` объявлен в начале `mainItemsImpl`
(`guard let strongSelf = self else { return .single(items) }`). `self.controller` — так узел профиля достаёт
контроллер в соседнем коде (`grep -n "self.controller" PeerInfoScreenPerformButtonAction.swift | head`). Если там
используется другое имя, взять его.

- [ ] **Шаг 4: контрольная точка**

```bash
git diff --check
```
```bash
grep -rn "dgToggleShadowBan" submodules/TelegramUI
```
Ожидается: `git diff --check` пуст, `grep` находит два вызова.

---

### Task 9: сверка всей ветки, чек-лист и коммиты по команде

**Файлы:** вся ветка `feat/shadow-ban`.

- [ ] **Шаг 1: статическая сверка**

```bash
git diff --stat origin/master
```
```bash
git diff --check origin/master
```
```bash
grep -rn "DonutgramShadowBan\." submodules Donutgram --include=*.swift
```
Ожидается:
- `git diff --stat` — 24 изменённых и 4 новых файла: `DonutgramShadowBan.swift`, `ShadowBanTests.swift`,
  `DGShadowBanController.swift`, план со спеком;
- `git diff --check` — пусто;
- `grep` — каждый вызов ссылается на функцию, объявленную в задаче 1. Сверить имена и метки параметров.

- [ ] **Шаг 2: независимая проверка диффа**

Отдать дифф свежему ревьюеру, который ищет:
- ошибки компиляции Swift: несовпадающие метки, Optional, захваты;
- нарушения `-warnings-as-errors`;
- расхождения со спеком.

Найденное исправить.

- [ ] **Шаг 3: стоп — ждать команды пользователя на коммит и пуш**

По команде сделать пять коммитов с явными списками файлов (без `-p` и `-i`):

```bash
git add Donutgram/DGSimpleSettings/Sources/DGSimpleSettings.swift submodules/TelegramCore/Sources/Donutgram/DonutgramShadowBan.swift Donutgram/DGFeatureTests/Tests/ShadowBanTests.swift docs/superpowers/specs/2026-10-04-shadow-ban-design.md docs/superpowers/plans/2026-10-04-shadow-ban.md
```
```bash
git commit -m "feat(shadow-ban): список и правило скрытия"
```
```bash
git add submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift submodules/TelegramUI/Sources/ChatHistoryListNode.swift submodules/TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift
```
```bash
git commit -m "feat(shadow-ban): скрытие в ленте сообщений"
```
```bash
git add submodules/ChatListUI/Sources/Node/ChatListItem.swift submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift submodules/ChatListUI/Sources/Node/ChatListNode.swift submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift submodules/TelegramUI/Components/Chat/ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift submodules/TelegramUI/Components/Chat/ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift submodules/TelegramUI/Components/Chat/ChatMessageInstantVideoItemNode/Sources/ChatMessageInstantVideoItemNode.swift submodules/TelegramUI/Components/Chat/ChatMessageInteractiveInstantVideoNode/Sources/ChatMessageInteractiveInstantVideoNode.swift submodules/TelegramUI/Sources/ApplicationContext.swift submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift submodules/TelegramUI/Sources/ChatControllerNode.swift submodules/TelegramUI/Sources/ChatSearchResultsContollerNode.swift submodules/TelegramUI/Sources/ChatController.swift
```
```bash
git commit -m "feat(shadow-ban): список чатов, цитаты, уведомления, поиск и закреп"
```
```bash
git add submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift submodules/TelegramUI/Components/Chat/ChatMessageReactionsFooterContentNode/Sources/ChatMessageReactionsFooterContentNode.swift submodules/Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift submodules/TelegramUI/Components/Chat/ChatMessageCommentFooterContentNode/Sources/ChatMessageCommentFooterContentNode.swift submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift
```
```bash
git commit -m "feat(shadow-ban): «печатает» в чате, реакции и сторис"
```
```bash
git add Donutgram/DGSettingsUI/BUILD Donutgram/DGSettingsUI/Sources/DGShadowBanController.swift Donutgram/DGSettingsUI/Sources/DGSettingLinks.swift Donutgram/DGSettingsUI/Sources/DGFeatureControllers.swift Donutgram/DGSettingsUI/Sources/DGSettingsController.swift submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift
```
```bash
git commit -m "feat(shadow-ban): меню сообщения, профиль и страница настроек"
```

Отличия от разбивки в спеке:
- «печатает…» в списке чатов ушло в коммит 3: это тот же файл `ChatListNode.swift`, что и перерисовка превью.
- Аватарки в шапке меню сообщения ушли в коммит 5: это тот же файл `ChatInterfaceStateContextMenus.swift`, что и
  пункт меню.

Делить файл между коммитами без интерактивного `git add -p` нельзя.

После коммитов `git status --short` должен быть пустым. Пуш и PR — тоже только по команде:
- PR на русском, без «ревью» и без упоминания Swiftgram;
- в описании — чек-лист из шага 4.

- [ ] **Шаг 4: чек-лист на телефоне для описания PR**

1. Забанить через меню сообщения: его сообщения уехали, «Отменить» вернуло их.
2. Группа, где он написал последним: превью пустое. После открытия и прокрутки вниз бейдж сбросился (фокус №2).
3. Длинные хвосты и куски скрытых (фокус №1). Ожидается: лента не мигает между сообщениями и спиннером, не уходит в
   бесконечную загрузку, внизу видно последнее видимое сообщение. Проверить:
   - 60 и 150 его сообщений подряд в конце чата — открыть группу;
   - пачка около 50 его сообщений, пока группа открыта внизу;
   - кусок около 120 его сообщений посередине — листать вверх через него.
4. Скрытое сообщение пришло, пока чат открыт внизу: после выхода у группы нет бейджа (фокус №2).
5. Ответ ему без цитаты. Нет баннера. Нет в глобальном поиске и поиске по чату. Нет в закрепе.
6. Нет его «печатает…» в группе и в списке. Нет его аватарок на реакциях, в «кто поставил» и под постами. Нет его
   сторис в ленте.
7. «Показать скрытые» вернуло его сообщения полупрозрачными, «Спрятать» снова убрало (фокус №4).
8. Личка с ним не изменилась.
9. С включённым режимом призрака прочтение скрытых не отправляет отметку «прочитано» (фокус №5). Проверять в обычной
   группе: в темах форума и комментариях Telegram читает тред в обход призрака и без теневого бана.
10. Страница в настройках: добавить через поиск, убрать свайпом, тап открывает профиль.
11. Тема форума и «Архив» со скрытым последним сообщением открываются тапом как раньше (фокус №3).
12. Разбан вернул всё.
