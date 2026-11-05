import Postbox

/// An ephemeral gallery item made from the bot's description, not a message stored in chat history.
/// The marker keeps sharing on the media path and prevents actions on its synthetic message id.
public final class DonutgramBotInfoMediaMessageAttribute: MessageAttribute {
    public let associatedMessageIds: [MessageId] = []
    public let associatedPeerIds: [PeerId] = []

    public init() {
    }

    public init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }
}

public func donutgramIsBotInfoMediaMessage(_ message: Message) -> Bool {
    return message.attributes.contains(where: { $0 is DonutgramBotInfoMediaMessageAttribute })
}
