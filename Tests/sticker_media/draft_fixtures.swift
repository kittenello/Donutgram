struct MessageTextEntity: Equatable {
    let id: Int
}

struct DraftInputState {
    enum Content {
        case textEntities(String, [MessageTextEntity])
        case instantPage
    }

    let replySubject: Int?
    let content: Content
    let timestamp: Int32
    let messageEffectId: Int?
    let suggestedPost: Int?
}

enum ChatListItemContent {
    struct DraftState {
        let draft: EngineChatList.Draft
    }
}

for reply in [nil, 1] as [Int?] {
    for text in ["", " ", "hello"] {
        for entities in [[], [MessageTextEntity(id: 1)]] {
            for effect in [nil, 1] as [Int?] {
                for suggestion in [nil, 1] as [Int?] {
                    let input = DraftInputState(replySubject: reply, content: .textEntities(text, entities), timestamp: 100, messageEffectId: effect, suggestedPost: suggestion)
                    let expected = reply != nil && text.isEmpty && entities.isEmpty && effect == nil && suggestion == nil
                    check(input.isEmptyReply == expected, "only a bare empty reply is classified as an empty reply")
                    let draft = EngineChatList.Draft(text: text, entities: entities, isEmptyReply: input.isEmptyReply)
                    for hidden in [false, true] {
                        let shown = chatListDraftState(draft, hideEmptyReplies: hidden)
                        check((shown == nil) == (hidden && expected), "the switch hides only an empty reply")
                        if let shown {
                            check(shown.draft == draft, "visible draft content remains intact")
                        }
                        check(chatListDraftState(nil, hideEmptyReplies: hidden) == nil, "no draft stays absent")
                        let expectedTime: Int32? = hidden && expected ? nil : 100
                        check(input.chatListTimestamp(hidingEmptyReplies: hidden) == expectedTime, "only a hidden empty reply keeps its chat in place")
                    }
                }
            }
        }
    }
    let structured = DraftInputState(replySubject: reply, content: .instantPage, timestamp: 100, messageEffectId: nil, suggestedPost: nil)
    check(!structured.isEmptyReply, "structured media drafts must not be hidden")
    check(structured.chatListTimestamp(hidingEmptyReplies: true) == 100, "a structured draft still moves its chat up")
}
let bareReply = EngineChatList.Draft(text: "", entities: [], isEmptyReply: true)
check(chatListDraftState(bareReply, hideEmptyReplies: true) == nil, "turning the switch on hides a saved empty reply")
check(chatListDraftState(bareReply, hideEmptyReplies: false) != nil, "turning it off restores the saved reply draft")
check(bareReply != EngineChatList.Draft(text: "", entities: []), "reply-only metadata participates in draft equality")
print("empty reply draft checks passed")
