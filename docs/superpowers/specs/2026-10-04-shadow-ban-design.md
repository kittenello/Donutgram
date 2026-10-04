# Теневой бан

**Дата:** 2026-10-04
**Статус:** дизайн согласован в чате по разделам; спек ждёт прочтения перед планом реализации.
**База:** `origin/master` c7bb57884c, ворктри `.claude/worktrees/shadow-ban`, ветка `feat/shadow-ban`.
Номера строк ниже даны «около» и сверены на c7bb57884c; план уточнит их перед правкой.

## Цель

Локальный теневой бан. Человек (пользователь, бот или канал) добавляется в список, и на этом устройстве
перестают быть видны его сообщения в группах, комментариях и каналах, а с ними следы его присутствия:
«печатает…», аватарки на реакциях и под постами, сторис. На сервер ничего не уходит, человек об этом не узнаёт.

Образец — Shadow Ban в AyuGram Desktop (`ayu/features/filters/filters_controller.cpp`,
`FiltersController::isBlocked`, коммит db3b989), с теми же границами: в личке ничего не прячется,
свои сообщения не прячутся, пересылки от забаненного прячутся.

## Решения из обсуждения

| Вопрос | Решение |
|---|---|
| Подход | Фильтр на уровне отображения: сообщения остаются в базе, каждое место интерфейса спрашивает одно общее правило. |
| Личка с забаненным | Не трогать. Лички вообще не фильтруются (как в AyuGram). |
| Что ещё прятать | «печатает…», реакции и аватарки, сторис. |
| Временный показ | «Показать скрытые» для конкретного чата, до перезапуска приложения. |
| Как банить | Меню сообщения, меню «…» профиля, страница в настройках Donutgram. |
| Отвергнуто | Фильтр в ядре (окна истории Postbox держат дыры и якоря по непрерывным индексам) и пометка или удаление при получении (разбан не вернёт удалённое, старые сообщения не затронет). |

## Что НЕ входит

- Лички с людьми и ботами, секретные чаты, «Избранное», личные сообщения каналу (monoforum).
- Вкладки «Медиа», «Файлы», «Ссылки», «Голосовые» в профиле группы. Сетка держит серверные счётчики
  и позиции, и выкидывание элементов её ломает. `ChatHistoryListNode` в режиме `.list` не фильтруется.
- Серверные счётчики:
  - бейджи непрочитанного и «@» у группы до её открытия;
  - бейдж на иконке приложения;
  - цифры реакций, комментариев и просмотров;
  - «N из M» за пределами загруженного.
- Пуш-уведомления. В сборке их нет: `disableExtensions` в `Telegram/BUILD`, `build.yml` удаляет
  `PlugIns`, шаблон entitlements без APNs.
- Участники голосовых чатов, проголосовавшие в опросах, список участников группы.
- Любые действия на сервере без открытия чата, например автопрочтение или гашение упоминаний. Они
  конфликтуют с режимом призрака.
- Синхронизация списка между устройствами.

## 1. Хранение — `DGSimpleSettings`

Файл `Donutgram/DGSimpleSettings/Sources/DGSimpleSettings.swift`.

- **Ключ.** `donutgram.spy.shadowBannedPeerIds` — массив строк с `PeerId.toInt64()`. Так же уже
  хранится `localPremiumPeerIds`. Список общий для всех аккаунтов, потому что упакованный `PeerId`
  один и тот же в любом аккаунте.
- **Кэш.** `Set<Int64>` в памяти под замком. Правило читают с главной очереди и с очередей Postbox,
  сотни раз на одно построение ленты. Кэш заполняется при первом обращении и меняется при записи.
- **«Показать скрытые».** `Set<Int64>` ID чатов, только в памяти и под тем же замком. В UserDefaults
  не пишется, поэтому сбрасывается при перезапуске.
- **Примерный интерфейс:**
  ```swift
  public static let shadowBanDidChangeNotification = Notification.Name("donutgram.shadowBan.didChange")
  public var shadowBannedPeerIds: Set<Int64> { get }
  public var hasShadowBans: Bool { get }                        // быстрый выход
  public func isShadowBanned(_ peerId: Int64) -> Bool
  public func setShadowBanned(_ banned: Bool, peerId: Int64)
  public var shadowBanRevealedChatIds: Set<Int64> { get }
  public func isShadowBanRevealed(chatPeerId: Int64) -> Bool
  public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64)
  ```
- **Уведомление.** Запись постит **только** `shadowBanDidChangeNotification`, без общего
  `didChangeNotification`. Общее уведомление заставляет `ManagedAccountPresence` слать
  `account.updateStatus` (нашлось в аудите паритета с AyuGram) и перерисовывает лишнее.

## 2. Правило скрытия — TelegramCore

Новый файл `submodules/TelegramCore/Sources/Donutgram/DonutgramShadowBan.swift`, рядом с
`DonutgramSpyStorage.swift`.
- TelegramCore уже зависит от `//Donutgram/DGSimpleSettings` и виден всем UI-модулям.
- UIKit не нужен, правило 7 из CLAUDE.md не нарушается.
- Новых обёрток TelegramEngine нет: это помощник форка, а не фасад Postbox.

### Подходящие чаты

| Чат | Фильтруется |
|---|---|
| `Namespaces.Peer.CloudGroup` (обычная группа) | да |
| `Namespaces.Peer.CloudChannel`: супергруппа, форум, канал, обсуждение | да, кроме monoforum (`peer.isMonoForum`) |
| Чат «Ответы» (`PeerId.isReplies`) | да, там ответы на твои комментарии |
| Пользователи, боты, секретки, «Избранное» | нет |

### Правило для сообщения

1. Список пуст → не скрыто (быстрый выход).
2. Чат `message.id.peerId` не подходит → не скрыто.
3. Сообщение не входящее (`!message.flags.contains(.Incoming)`) → не скрыто.
4. Чат в «Показать скрытые» → не скрыто.
5. Скрыто, если выполнено хотя бы одно:
   - `message.author?.id` в бане **и** не равен `message.id.peerId` (посты забаненного канала в нём
     самом видны);
   - `message.forwardInfo?.author?.id` или `message.forwardInfo?.source?.id` в бане;
   - `InlineBotMessageAttribute.peerId` в бане.
6. Иначе не скрыто.

Служебные сообщения от забаненного («закрепил», «вступил») скрываются по п. 5, это его действия.
Ответы других людей забаненному остаются, у них прячется только цитата (раздел 4).

### Примерный интерфейс

```swift
public enum DonutgramShadowBan {
    public struct State: Equatable {                 // снимок для фоновых вычислений
        public var bannedPeerIds: Set<Int64>
        public var revealedChatIds: Set<Int64>
        public static var current: State { get }
    }
    public static func isHidden(_ message: Message, state: State) -> Bool   // чистая функция, на неё тесты
    public static func isHidden(_ message: Message) -> Bool                 // со State.current
    public static func isHidden(_ message: EngineMessage) -> Bool
    public static func isBannedContent(_ message: Message) -> Bool          // без учёта «Показать скрытые»
    public static func isPeerHidden(_ peerId: PeerId, inChat chatPeerId: PeerId, state: State = .current) -> Bool  // «печатает», аватарки
    public static func stateSignal() -> Signal<State, NoError>              // текущее + изменения
}
```

`isPeerHidden` верно, если выполнено всё сразу:
- список не пуст;
- чат подходит и не раскрыт;
- `peerId` в бане и не равен самому чату.

В раскрытом чате «Показать скрытые» возвращает и сообщения, и следы присутствия.

У «печатает…» и аватарок решение принимается только по ID чата (по namespace), потому что объект чата там почти
нигде не доступен. Поэтому monoforum для них считается каналом. Для сообщений объект чата берётся из
`message.peers[message.id.peerId]`, и monoforum распознаётся.

## 3. Лента сообщений

### Фильтр

- **Где.** `submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift`, `chatHistoryEntriesForView(...)`.
- **Вход.** Функция получает снимок `DonutgramShadowBan.State`.
- **Проверка.** В цикле `for entry in view.entries` (около L144), сразу после проверки
  `pendingRemovedMessages` (около L153–155), стоит `continue` для `isHidden(message, state:)`.
- **Альбомы.** Проверка идёт до группировки (около L253–299), поэтому альбом пропадает целиком.
- **Шапка треда.** Корневое сообщение из `view.additionalData` (около L463–524) не фильтруется.
- **Даты.** Заголовки дат строятся из соседних сообщений и правки не требуют.
- **Счётчик скрытых.** Функция возвращает число скрытых в окне, и вид его хранит (например,
  `ChatHistoryView.donutgramHiddenCount`). Все починки ниже включаются только при значении больше нуля.
  Если окно ничего не скрыло, код Telegram работает как раньше.
- **Режим.** Фильтр работает только в режиме `.bubbles`.

### Обновление на лету

- **Где.** `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`.
- **Промис.** Промис состояния устроен по образцу `pendingRemovedMessagesPromise` (около L648–655).
  Цепочка: `promises` (около L1850–1858) → большой `combineLatest` (около L1942–1969) → вызов функции
  записей (около L2262).
- **Источник.** Промис наполняет наблюдатель `shadowBanDidChangeNotification`.
- **Пересчёт.** Смена списка или раскрытия даёт пересчёт с `.InteractiveChanges` (около L2302–2304):
  анимированно и без прыжка скролла.
- **Цитаты.** После пересчёта вызывается `updateLoadedMessageItems(includeAllMessages: true)`, чтобы
  перерисовать шапки ответов.

### Починки, когда в окне есть скрытые

1. **Якорь подгрузки.** `processDisplayedItemRangeChanged`, около L3458–3525.
   - Сейчас `.Navigation(index: .message(...))` строится от `filteredEntries.first/last`. Если подряд
     скрыто больше ~22 сообщений, новое окно даёт те же видимые записи, а повтор запроса блокирует
     `content != locationInput`.
   - Якорь берётся от `historyView.originalView.entries.first/last`.
2. **Пустое окно.** Около L4214–4258.
   - Сейчас при пустом `filteredEntries` ставится `.empty`, то есть заглушка «нет сообщений», и
     подгрузка больше не запускается: нет видимого диапазона.
   - Если `originalView.entries` не пуст, ставится `.loading(false)` и запрашивается следующее окно:
     к более новым при `laterId != nil`, иначе к более старым при `earlierId != nil`.
   - Повтор для того же якоря не отправляется.
   - `.empty` ставится, только когда грузить больше нечего.
3. **Прочтение по видимым.** `visibleContentOffsetChanged`, около L1106–1201.
   - Найденный по видимым пузырям `maxMessage` продлевается до последнего сообщения окна перед
     следующей видимой записью. Если следующей видимой записи нет, продлевается до конца окна.
   - Окно непрерывно, поэтому всё, что лежит между, скрыто.
   - Без этой починки при последнем сообщении от забаненного бейдж у группы не сбросится никогда.
4. **Прочтение без изменения списка.**
   - `ListView.transaction` при пустых изменениях только подменяет `opaqueTransactionState` и не
     вызывает ни `visibleContentOffsetChanged`, ни `displayedItemRangeChanged`. Поэтому скрытое
     сообщение, пришедшее, пока чат открыт и прокручен вниз, сейчас не читается.
   - После применения такого перехода вызывается расчёт из п. 3, а затем
     `listView.updateVisibleItemRange(force: true)`, ради п. 5.
5. **Скрытые упоминания.** `processDisplayedItemRangeChanged`, около L2967–3156.
   - В `messageIdsWithUnseenPersonalMention` добавляются скрытые сообщения окна с тегом
     `.unseenPersonalMessage`, которые лежат между соседями видимого диапазона. Границы те же, что
     считает `maxMessageIndexForEntries` (около L157–198).
6. **Режим призрака.** Прочтение и гашение идут через существующие
   `updateMaxVisibleReadIncomingMessageIndex` и `messageMentionProcessingManager`, тем же путём и с
   теми же проверками, что и для видимых сообщений.

### «Показать скрытые»

`ChatMessageItemView.swift` (около L693–696) делает удалёнки полупрозрачными (alpha 0.55). Показанные
скрытые получают ту же полупрозрачность: чат раскрыт и `isBannedContent(message)` верно.

## 4. Остальные места

| Место | Файл (около строки) | Что делаем |
|---|---|---|
| Превью в списке чатов, темы форума | `ChatListUI/Sources/Node/ChatListItem.swift` L2486–2492, рядом с `.historyCleared` | Если `messages.last` скрыто, `messages = []`. Дата остаётся: она берётся из `peerData.messages.first` (около L3376). |
| Строка «Архив» | `ChatListUI/Sources/Node/ChatListNodeEntries.swift` около L934 (`groupReference.topMessage`) | Скрытое сообщение не попадает в превью. |
| Перерисовка списка чатов | `ChatListUI/Sources/Node/ChatListNode.swift` | Наблюдатель `shadowBanDidChangeNotification` пересобирает элементы (образец — `ChatListControllerNode` около L1339). |
| Цитата в ответе | `ChatMessageBubbleItemNode` (около L2135–2143); сборка шапки ответа в `ChatMessageAnimatedStickerItemNode`, `ChatMessageStickerItemNode`, `ChatMessageInstantVideoItemNode`, `ChatMessageInteractiveInstantVideoNode` | Если исходное сообщение скрыто, `replyMessage`/`replyQuote` = nil и шапки нет. Для ответа на сообщение из другого чата (`QuotedReplyMessageAttribute`, известен только `peerId`) решение принимается по `peerId` автора. Общий помощник живёт в `DonutgramShadowBan`. |
| Баннер внутри приложения | `TelegramUI/Sources/ApplicationContext.swift` около L306 (`messageList.filter`) | Скрытые выкидываются до звука и вибрации (около L376–393) и до баннера (около L422). |
| Глобальный поиск | `ChatListUI/Sources/ChatListSearchListPaneNode.swift` около L3431, а также около L3390 и L3410 (посты) | `continue` для скрытых. |
| Поиск в чате | `TelegramUI/Sources/ChatControllerUpdateSearch.swift`, `Chat/ChatControllerLoadDisplayNode.swift` около L1199 и L2402–2406, `ChatControllerNode.swift` около L3460 | Фильтруется `SearchMessagesResult.messages`, `totalCount` уменьшается на число выкинутых. |
| Закреп | `TelegramUI/Sources/ChatController.swift` около L7458–7547 | Скрытые выкидываются из `PinnedHistory.messages`, индексы и `totalCount` пересчитываются. Если верхний закреп скрыт, берётся следующий видимый. |
| «печатает…» в шапке | `Chat/ChatControllerLoadDisplayNode.swift` около L5155 (`peerInputActivities`) | Действия забаненных выкидываются, если `isPeerHidden`. |
| «печатает…» в списке | `ChatListUI/Sources/Node/ChatListNode.swift` около L2756–2770, рядом с выкидыванием `.interactingWithEmoji` | То же, ключ — чат. |
| Аватарки на реакциях | `ChatMessageReactionsFooterContentNode.swift` около L187–198 (`ChatMessageReactionButtonsNode`) | Забаненные выкидываются из `peers`. При `peers.count != reaction.count` кнопка сама показывает цифру. |
| «Кто поставил / просмотрел» | `submodules/Components/ReactionListContextMenuContent`; аватарки в шапке меню, `ChatInterfaceStateContextMenus.swift` около L3762 | Забаненные выкидываются из списка и аватарок. Цифры на вкладках остаются. |
| Аватарки под постом канала | `ChatMessageCommentFooterContentNode.swift` около L133 (`latestUsers`) | Забаненные выкидываются. |
| Сторис | `TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift` около L1017, `storySubscriptions(isHidden:tempKeepNewlyArchived:)` | `combineLatest` со `stateSignal()`: забаненные выкидываются из `items`, `accountItem` не трогается. Покрывает ленту над чатами и архивом (`ChatListController` около L2188 и L2248), пролистывание подряд (`StoryChatContent.swift` около L734) и камеру (`CameraScreen.swift` около L1187). В профиле сторис открываются как обычно. |

Превью «отреагировал» в списке чатов (`ChatListItem` около L2632–2652) строится только для личек и
правки не требует.

## 5. Управление

### Меню сообщения

- **Где.** `TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`, рядом с «Заблокировать»
  (около L1937–1949).
- **Пункт.** «Теневой бан» показывается у входящего сообщения в подходящем чате, если
  `message.author` — пользователь, бот или канал, не ты и не сам чат. Анонимного админа и пост канала
  в самом канале забанить нельзя.
- **Пересылки.** Банится тот, кто переслал. Автор оригинала банится из своего профиля.
- **Чат «Ответы».** Там автором показан `forwardInfo.author` (так его выводит `ChatMessageBubbleItemNode`
  около L1720), поэтому банится он, а не `message.author`.
- **После нажатия.** `UndoOverlayController` с текстом «<Имя> в теневом бане» и кнопкой «Отменить».

### Меню «…» профиля

- **Где.** `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift`:
  `case .more:` (около L379), ветка пользователя (около L479) рядом с «Заблокировать»
  (около L861–891), ветка каналов.
- **Пункт.** «Теневой бан» или «Убрать из теневого бана» для пользователей, ботов и каналов, кроме
  себя. После нажатия тот же тост.
- **Личка не мешает.** Забанить можно и того, с кем есть личка: бан действует только в подходящих чатах.

### «Показать скрытые»

- **Где.** Там же, в ветке групп и каналов.
- **Когда виден.** Только при непустом списке бана.
- **Текст.** «Показать скрытые сообщения» ↔ «Спрятать скрытые сообщения».
- **Ключ.** ID чата. Для комментариев это группа обсуждения.

### Страница в настройках

- **Ссылка и место.** Новый случай `DGSettingsPage.shadowBan = "shadow-ban"` в `DGSettingLinks.swift`,
  то есть `tg://settings/donutgram/shadow-ban`.
  - Строка «Теневой бан» с числом забаненных стоит в `dgSpySettingsController` («Основные»).
  - Фабрика добавляется в `dgSettingsControllerForLink` (`DGFeatureControllers.swift`).
- **Экран.** `ItemListController` по образцу
  `SettingsUI/Sources/Privacy and Security/BlockedPeersController.swift`:
  - кнопка «Добавить» открывает `makePeerSelectionController` с людьми, ботами и каналами из чатов и поиска;
  - список `ItemListPeerItem` поддерживает свайп «Убрать» и режим «Изменить»;
  - тап по строке открывает профиль;
  - ID, неизвестный текущему аккаунту, показывается строкой «Неизвестный · ID …», и его можно убрать.
- **Подпись.** «Сообщения этих людей скрыты в группах, комментариях и каналах только на этом
  устройстве. Они об этом не узнают. Личные чаты не меняются».
- **Зависимости.** В `Donutgram/DGSettingsUI/BUILD` добавляются `//submodules/ItemListPeerItem` и
  `//submodules/ItemListPeerActionItem`.

Иконки пунктов меню выбираются из уже имеющихся в бандле; конкретные выберет план.

## 6. Известные ограничения

- Серверные счётчики не меняются (см. «Что НЕ входит»).
- В длинных списках закрепов и в поиске счёт пересчитывается только по загруженной части.
- Кнопка «@», ведущая к скрытому упоминанию, ставит ленту на ближайшее видимое сообщение, а
  упоминание гасится.
- Если подряд скрыто очень много сообщений, лента загружает окно за окном до первого видимого
  сообщения или до конца истории. Это чтение локальной базы или обычные запросы истории.
- Список живёт только в UserDefaults этого устройства, переустановка приложения его стирает.

## 7. Проверка

### Тесты

Новый файл `Donutgram/DGFeatureTests/Tests/ShadowBanTests.swift`. Зависимости цели
(`DGSimpleSettings`, `Postbox`, `TelegramCore`) уже есть. Случаи для чистого
`isHidden(_:state:)`:

| Ситуация | Ожидание |
|---|---|
| Автор в бане, супергруппа | скрыто |
| Автор в бане, обычная группа | скрыто |
| Автор в бане, личка с ним | видно |
| Автор в бане, секретный чат | видно |
| Своё (не `.Incoming`) сообщение | видно |
| Пересылка, `forwardInfo.author` в бане, группа | скрыто |
| Пересылка, `forwardInfo.source` (канал) в бане, канал | скрыто |
| Пересылка от забаненного в личке | видно |
| Через забаненного inline-бота | скрыто |
| Пост забаненного канала в самом канале | видно |
| Служебное сообщение от забаненного | скрыто |
| Чат «Ответы», пересылка от забаненного | скрыто |
| Monoforum канала | видно |
| Чат в «Показать скрытые» | видно, а `isBannedContent` верно |
| Пустой список | видно |

Хранение проверяется так: добавить, убрать, перечитать из UserDefaults. После теста ключ очищается.

**Ограничение.** Тесты запускаются только на Маке
(`Make.py test --target //Donutgram/DGFeatureTests:DGFeatureTests`). CI их не гоняет: `build.yml`
только собирает IPA. Компиляцию проверяет сборка PR на CI, поведение — проверка на телефоне.

### Чек-лист на телефоне (пойдёт в описание PR)

1. Забанить через меню сообщения: его сообщения уехали, «Отменить» вернуло их.
2. Группа, где он написал последним: превью пустое; после открытия и прокрутки вниз бейдж сбросился.
3. Его спам на 50+ сообщений подряд: лента листается вверх без затыка, вместо «нет сообщений» видна
   загрузка.
4. Скрытое сообщение пришло, пока чат открыт внизу: после выхода у группы нет бейджа.
5. Ответ ему без цитаты. Нет баннера. Нет в глобальном поиске и поиске по чату. Нет в закрепе.
6. Нет его «печатает…» в группе и в списке, его аватарок на реакциях, в «кто поставил» и под
   постами, его сторис в ленте.
7. «Показать скрытые» вернуло его сообщения полупрозрачными, «Спрятать» снова убрало.
8. Личка с ним не изменилась.
9. С включённым режимом призрака прочтение скрытых не отправляет отметку «прочитано».
10. Страница в настройках: добавить через поиск, убрать свайпом, тап открывает профиль.
11. Разбан вернул всё.

## 8. Сдача

- Работа идёт в ворктри `.claude/worktrees/shadow-ban` на ветке `feat/shadow-ban`. Коммиты и пуши —
  только по команде.
- Один PR, пять коммитов на русском (conventional):
  1. `feat(shadow-ban): список и правило скрытия` — `DGSimpleSettings`, `DonutgramShadowBan`, тесты;
  2. `feat(shadow-ban): скрытие в ленте сообщений` — фильтр, подгрузка, прочтение, упоминания,
     полупрозрачность показанных;
  3. `feat(shadow-ban): список чатов, цитаты, уведомления, поиск и закреп`;
  4. `feat(shadow-ban): «печатает», реакции и сторис`;
  5. `feat(shadow-ban): меню, профиль и страница настроек`.
- В тексте PR нет слова «ревью» и не упоминается Swiftgram. Описание — чек-лист из раздела 7.
