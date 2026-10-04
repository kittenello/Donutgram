import Foundation
import Display
import TelegramCore
import TelegramPresentationData
import DGSimpleSettings

/// Shared by inline message buttons and the bot reply keyboard. Copying never invokes the button.
public func presentBotButtonContextMenu(button: ReplyMarkupButton, presentationData: PresentationData, interaction: ChatControllerInteraction, message: EngineRawMessage?) {
    let controller = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: button.title, parseMarkdown: false)]
    items.append(ActionSheetButtonItem(title: dgLocalized("Копировать название", languageCode: presentationData.strings.baseLanguageCode), action: { [weak controller] in
        controller?.dismissAnimated()
        interaction.copyText(button.title)
    }))
    if case let .callback(_, buffer) = button.action {
        let data = buffer.makeData()
        // Callback payloads are arbitrary bytes. Preserve non-UTF-8 payloads as a reversible hex string.
        let text = String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()
        items.append(ActionSheetButtonItem(title: dgLocalized("Копировать Callback-данные", languageCode: presentationData.strings.baseLanguageCode), action: { [weak controller] in
            controller?.dismissAnimated()
            interaction.copyText(text)
        }))
    }
    if case let .url(url) = button.action {
        items.append(ActionSheetButtonItem(title: dgLocalized("Меню ссылки", languageCode: presentationData.strings.baseLanguageCode), action: { [weak controller] in
            controller?.dismissAnimated()
            interaction.longTap(.url(url), ChatControllerInteraction.LongTapParams(message: message))
        }))
    }
    controller.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak controller] in
            controller?.dismissAnimated()
        })])
    ])
    interaction.presentController(controller, nil)
}
