import Foundation
import UIKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData

struct DGPluginListContent {
    let icon: UIImage
    let title: String
    let subtitle: String
    let description: String
    let enabled: Bool
    let interactive: Bool
    let actions: [String]
}

final class DGPluginListItem: ListViewItem, ItemListItem {
    let sectionId: ItemListSectionId
    let theme: PresentationTheme
    let content: DGPluginListContent
    let scale: CGFloat
    let open: () -> Void
    let toggle: (Bool) -> Void
    let action: (Int) -> Void

    init(sectionId: ItemListSectionId, theme: PresentationTheme, content: DGPluginListContent, scale: CGFloat, open: @escaping () -> Void, toggle: @escaping (Bool) -> Void, action: @escaping (Int) -> Void) {
        self.sectionId = sectionId
        self.theme = theme
        self.content = content
        self.scale = min(2, max(0.8, scale))
        self.open = open
        self.toggle = toggle
        self.action = action
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = DGPluginListItemNode()
            let calculate = node.asyncLayout()
            async {
                let (layout, apply) = calculate(self, params, neighbors)
                Queue.mainQueue().async {
                    node.contentSize = layout.contentSize
                    node.insets = layout.insets
                    completion(node, { (nil, { _ in apply() }) })
                }
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? DGPluginListItemNode else { return }
            let layout = node.asyncLayout()
            async {
                let (result, apply) = layout(self, params, neighbors)
                Queue.mainQueue().async { completion(result, { _ in apply() }) }
            }
        }
    }
}

private struct DGPluginListLayout {
    let frames: DGPluginCardLayout
    let height: CGFloat
    let titleHeight: CGFloat
    let subtitleHeight: CGFloat
    let descriptionHeight: CGFloat
    let headingHeight: CGFloat
    let actionHeight: CGFloat

    init(item: DGPluginListItem, width: CGFloat) {
        let headingWidth = max(1, width - 32 - 44 - 12 - 51 - 12)
        func measure(_ text: String, size: CGFloat, width: CGFloat, lines: Int, weight: UIFont.Weight = .regular) -> CGFloat {
            let font = UIFont.systemFont(ofSize: size * item.scale, weight: weight)
            return min(ceil(font.lineHeight * CGFloat(lines)), DGPluginNativeItem.textHeight(NSAttributedString(string: text, attributes: [.font: font]), width: width))
        }
        self.titleHeight = measure(item.content.title, size: 17, width: headingWidth, lines: 2, weight: .medium)
        self.subtitleHeight = measure(item.content.subtitle, size: 12, width: headingWidth, lines: 2)
        self.headingHeight = max(44, self.titleHeight + 3 + self.subtitleHeight)
        self.descriptionHeight = measure(item.content.description, size: 14, width: max(1, width - 32), lines: 2)
        let actionWidth = max(1, (width - 32) / 3 - 4)
        let labelHeight = item.content.actions.map { measure($0, size: 11, width: actionWidth, lines: 2) }.max() ?? 0
        self.actionHeight = max(48, 18 + 4 + labelHeight + 10)
        let frames = DGPluginCardLayout(width: width, titleHeight: self.titleHeight, subtitleHeight: self.subtitleHeight, descriptionHeight: self.descriptionHeight, actionLabelHeight: labelHeight)
        self.frames = frames
        self.height = frames.height
    }
}

private final class DGPluginListActionButton: UIButton {
    let glyph = UIImageView()
    let caption = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.glyph)
        self.addSubview(self.caption)
        self.glyph.contentMode = .scaleAspectFit
        self.caption.textAlignment = .center
        self.caption.numberOfLines = 2
        self.isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { return nil }

    override var isHighlighted: Bool {
        didSet { self.alpha = self.isHighlighted ? 0.5 : (self.isEnabled ? 1 : 0.4) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.glyph.frame = CGRect(x: floor((self.bounds.width - 18) / 2), y: 5, width: 18, height: 18)
        self.caption.frame = CGRect(x: 2, y: 27, width: max(1, self.bounds.width - 4), height: max(1, self.bounds.height - 30))
    }
}

private final class DGPluginListItemNode: ListViewItemNode {
    private let block = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let headingButton = UIButton()
    private let enabledSwitch = UISwitch()
    private let separator = UIView()
    private let buttons = (0 ..< 3).map { _ in DGPluginListActionButton(frame: .zero) }
    private var item: DGPluginListItem?
    private var params: ListViewItemLayoutParams?
    private var geometry: DGPluginListLayout?

    init() { super.init(layerBacked: false) }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.block)
        self.block.layer.cornerRadius = 18
        self.block.clipsToBounds = true
        for view in [self.imageView, self.titleLabel, self.subtitleLabel, self.descriptionLabel, self.headingButton, self.enabledSwitch, self.separator] { self.block.addSubview(view) }
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.layer.cornerRadius = 12
        self.imageView.clipsToBounds = true
        self.titleLabel.numberOfLines = 2
        self.subtitleLabel.numberOfLines = 2
        self.descriptionLabel.numberOfLines = 2
        self.titleLabel.isAccessibilityElement = false
        self.subtitleLabel.isAccessibilityElement = false
        self.headingButton.setBackgroundImage(UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }, for: .normal)
        self.headingButton.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        self.enabledSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        for (index, button) in self.buttons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
            self.block.addSubview(button)
        }
        self.apply()
    }

    func asyncLayout() -> (DGPluginListItem, ListViewItemLayoutParams, ListViewItemNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let width = max(1, params.width - params.leftInset - params.rightInset)
            let geometry = DGPluginListLayout(item: item, width: width)
            let itemNeighbors = itemListNeighbors(item: item, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self))
            var insets = itemListNeighborsGroupedInsets(itemNeighbors, params)
            if case .otherSection = itemNeighbors.top { insets.top = 10 }
            if case .none = itemNeighbors.bottom { insets.bottom = 16 }
            return (ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: geometry.height), insets: insets), { [weak self] in
                self?.item = item
                self?.params = params
                self?.geometry = geometry
                self?.apply()
            })
        }
    }

    private func apply() {
        guard self.isNodeLoaded, let item = self.item, let params = self.params, let geometry = self.geometry else { return }
        let width = max(1, params.width - params.leftInset - params.rightInset)
        self.block.frame = CGRect(x: params.leftInset, y: 0, width: width, height: geometry.height)
        self.block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        let primary = item.theme.list.itemPrimaryTextColor
        let secondary = item.theme.list.itemSecondaryTextColor
        let accent = item.theme.list.itemAccentColor
        self.imageView.image = item.content.icon
        self.imageView.frame = geometry.frames.icon
        self.imageView.alpha = item.content.enabled ? 1 : 0.55
        self.titleLabel.text = item.content.title
        self.titleLabel.font = .systemFont(ofSize: 17 * item.scale, weight: .medium)
        self.titleLabel.textColor = primary
        self.titleLabel.frame = geometry.frames.title
        self.subtitleLabel.text = item.content.subtitle
        self.subtitleLabel.font = .systemFont(ofSize: 12 * item.scale)
        self.subtitleLabel.textColor = secondary
        self.subtitleLabel.frame = geometry.frames.subtitle
        self.headingButton.frame = geometry.frames.headingButton
        self.headingButton.accessibilityLabel = item.content.title + ", " + item.content.subtitle
        self.headingButton.isEnabled = item.content.interactive
        self.enabledSwitch.frame = geometry.frames.toggle
        self.enabledSwitch.onTintColor = accent
        self.enabledSwitch.setOn(item.content.enabled, animated: false)
        self.enabledSwitch.isEnabled = item.content.interactive
        self.enabledSwitch.accessibilityLabel = item.content.title
        self.descriptionLabel.text = item.content.description
        self.descriptionLabel.font = .systemFont(ofSize: 14 * item.scale)
        self.descriptionLabel.textColor = secondary
        self.descriptionLabel.frame = geometry.frames.description
        self.separator.backgroundColor = item.theme.list.itemBlocksSeparatorColor
        self.separator.frame = CGRect(x: geometry.frames.separator.minX, y: geometry.frames.separator.minY, width: geometry.frames.separator.width, height: 1 / UIScreen.main.scale)
        for (index, button) in self.buttons.enumerated() {
            let color = index == 0 ? accent : secondary
            button.caption.text = item.content.actions[index]
            button.caption.font = .systemFont(ofSize: 11 * item.scale)
            button.caption.textColor = color
            button.glyph.tintColor = index == 2 ? item.theme.list.itemDestructiveColor : color
            if #available(iOS 13.0, *) { button.glyph.image = UIImage(systemName: ["slider.horizontal.3", "arrowshape.turn.up.right", "trash"][index]) }
            button.accessibilityLabel = item.content.actions[index] + ": " + item.content.title
            button.isEnabled = item.content.interactive
            button.alpha = item.content.interactive ? 1 : 0.4
            button.frame = geometry.frames.actions[index]
        }
    }

    @objc private func openPressed() { self.item?.open() }
    @objc private func switchChanged() { self.item?.toggle(self.enabledSwitch.isOn) }
    @objc private func actionPressed(_ sender: UIButton) { self.item?.action(sender.tag) }
}
