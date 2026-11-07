import Foundation

enum ChatMessageReplyInfoType { case bubble(incoming: Bool); case standalone }
enum ChatMessageBubbleStyle: Equatable, CaseIterable { case bubble; case bubbleless; case bubblelessCard }
typealias ChatPresentationData = Int
typealias PresentationStrings = Int
typealias AccountContext = Int
typealias EngineRawMessage = Int
typealias QuotedReplyMessageAttribute = Int
typealias EngineMessageReplyQuote = Int
typealias EngineMessageReplyInnerSubject = Int
typealias EngineStoryId = Int
typealias AnimationCache = Int
typealias MultiAnimationRenderer = Int
typealias ChatMessageItemAssociatedData = Int

struct Arguments {}

func sanitized(_ arguments: Arguments) -> Arguments {
    return arguments
}

for style in ChatMessageBubbleStyle.allCases {
    for hidden in [false, true] {
        for loading in [false, true] {
            let original = Arguments(
                presentationData: 11, strings: 12, context: 13, type: .bubble(incoming: true),
                message: 14, replyForward: 15, quote: (quote: 16, isQuote: true), innerSubject: 17, story: 18,
                isSummarized: false, isLoading: loading, parentMessage: 19,
                constrainedSize: CGSize(width: 200, height: 70), animationCache: 20,
                animationRenderer: 21, associatedData: 22, bubbleStyle: style, donutgramHidden: hidden
            )
            let result = sanitized(original)
            precondition(result.presentationData == 11 && result.strings == 12 && result.context == 13)
            precondition(result.parentMessage == 19 && result.associatedData == 22)
            precondition(result.constrainedSize.width == original.constrainedSize.width && result.constrainedSize.height == original.constrainedSize.height)
            precondition(result.animationCache == 20 && result.animationRenderer == 21)
            precondition(result.bubbleStyle == style && result.donutgramHidden == hidden)
            if hidden {
                precondition(result !== original)
                precondition(result.message == nil && result.replyForward == nil && result.quote == nil)
                precondition(result.innerSubject == nil && result.story == nil)
                precondition(!result.isLoading, "a hidden reply must settle as a placeholder")
            } else {
                precondition(result === original, "visible reply arguments keep their identity")
                precondition(result.message == 14 && result.replyForward == 15 && result.quote?.quote == 16)
                precondition(result.quote?.isQuote == true && result.innerSubject == 17 && result.story == 18)
                precondition(result.isLoading == loading, "visible replies retain their loading state")
            }
        }
    }
}
print("reply privacy, loading and bubble-style checks passed")
