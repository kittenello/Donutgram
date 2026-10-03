import UIKit
import DGSimpleSettings
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils

final class DGStickerAppearanceItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let languageCode: String
    let sectionId: ItemListSectionId
    let shapePicker: Bool
    let size: Int
    let shape: Int
    let updated: (String) -> Void

    init(theme: PresentationTheme, languageCode: String, sectionId: ItemListSectionId, shapePicker: Bool, size: Int, shape: Int, updated: @escaping (String) -> Void) {
        self.theme = theme
        self.languageCode = languageCode
        self.sectionId = sectionId
        self.shapePicker = shapePicker
        self.size = size
        self.shape = shape
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = DGStickerAppearanceItemNode()
            let (layout, apply) = node.layout(self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { (nil, { _ in apply() }) })
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? DGStickerAppearanceItemNode else { return }
            let (layout, apply) = node.layout(self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            completion(layout, { _ in apply() })
        }
    }
}

private final class DGStickerAppearanceItemNode: ListViewItemNode, ItemListItemNode {
    private var item: DGStickerAppearanceItem?
    var tag: ItemListItemTag? { item.map { DGSettingItemTag(key: $0.shapePicker ? "stickerShape" : "stickerSize") } }
    private let block = UIView()
    private let mask = ASImageNode()
    private let title = UILabel()
    private let small = UILabel()
    private let large = UILabel()
    private let slider = UISlider()
    private let reset = UIButton(type: .system)
    private var shapeButtons: [UIButton] = []
    private var shapeSamples: [UIView] = []
    private var shapeLabels: [UILabel] = []

    init() { super.init(layerBacked: false) }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(block)
        for subview in [title, small, large, slider, reset] as [UIView] { block.addSubview(subview) }
        self.addSubnode(mask)
        mask.isUserInteractionEnabled = false
        title.font = .systemFont(ofSize: 15, weight: .medium)
        small.font = .systemFont(ofSize: 12)
        large.font = .systemFont(ofSize: 12)
        small.text = "Маленький"
        large.text = "Большой"
        large.textAlignment = .right
        slider.minimumValue = 1
        slider.maximumValue = 20
        slider.isContinuous = true
        slider.disablesInteractiveTransitionGestureRecognizer = true
        slider.accessibilityLabel = "Размер стикеров"
        slider.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        reset.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        reset.accessibilityLabel = "Сбросить настройки стикеров"
        reset.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        for (index, text) in ["По умолчанию", "Закруглённая", "Сообщение"].enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.accessibilityLabel = text
            button.layer.cornerRadius = 12
            button.addTarget(self, action: #selector(shapePressed(_:)), for: .touchUpInside)
            let sample = UIView()
            sample.isUserInteractionEnabled = false
            sample.layer.cornerRadius = index == 0 ? 0 : (index == 1 ? 12 : 22)
            button.addSubview(sample)
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 11)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.textAlignment = .center
            block.addSubview(button)
            block.addSubview(label)
            shapeButtons.append(button)
            shapeSamples.append(sample)
            shapeLabels.append(label)
        }
    }

    func displayHighlight() {
        guard let item else { return }
        dgDisplayHighlight(in: block, theme: item.theme)
    }

    func layout(_ item: DGStickerAppearanceItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let width = max(100, params.width - params.leftInset - params.rightInset)
        let cardSide = min(84, (width - 48) / 3)
        let height: CGFloat = item.shapePicker ? cardSide + 52 : 104
        let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: itemListNeighborsGroupedInsets(neighbors, params))
        return (layout, { [weak self] in
            guard let self else { return }
            self.view.backgroundColor = .clear
            self.item = item
            self.block.frame = CGRect(x: params.leftInset, y: 0, width: width, height: height)
            self.block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            var topCorners = true
            var bottomCorners = true
            if case .sameSection(false) = neighbors.top { topCorners = false }
            if case .sameSection(false) = neighbors.bottom { bottomCorners = false }
            self.mask.image = itemListHasRoundedBlockLayout(params) ? PresentationResourcesItemList.cornersImage(item.theme, top: topCorners, bottom: bottomCorners, glass: true) : nil
            self.mask.frame = self.block.frame
            let accent = item.theme.list.itemAccentColor
            self.title.text = dgLocalized("Размер стикеров", languageCode: item.languageCode) + "  \(item.size)"
            self.small.text = dgLocalized("Маленький", languageCode: item.languageCode)
            self.large.text = dgLocalized("Большой", languageCode: item.languageCode)
            self.slider.accessibilityLabel = dgLocalized("Размер стикеров", languageCode: item.languageCode)
            self.reset.accessibilityLabel = dgLocalized("Сбросить настройки стикеров", languageCode: item.languageCode)
            for (index, title) in ["По умолчанию", "Закруглённая", "Сообщение"].enumerated() {
                let text = dgLocalized(title, languageCode: item.languageCode)
                self.shapeLabels[index].text = text
                self.shapeButtons[index].accessibilityLabel = text
            }
            self.title.textColor = accent
            self.title.frame = CGRect(x: 16, y: 10, width: width - 70, height: 24)
            self.reset.frame = CGRect(x: width - 48, y: 6, width: 40, height: 36)
            self.reset.tintColor = accent
            self.small.textColor = item.theme.list.itemSecondaryTextColor
            self.large.textColor = item.theme.list.itemSecondaryTextColor
            self.small.frame = CGRect(x: 16, y: 39, width: 100, height: 18)
            self.large.frame = CGRect(x: width - 116, y: 39, width: 100, height: 18)
            if !self.slider.isTracking { self.slider.value = Float(item.size) }
            self.slider.accessibilityValue = "\(item.size)"
            self.slider.minimumTrackTintColor = accent
            self.slider.maximumTrackTintColor = item.theme.list.itemSecondaryTextColor.withAlphaComponent(0.25)
            self.slider.frame = CGRect(x: 16, y: 63, width: width - 32, height: 32)
            for view in [self.title, self.small, self.large, self.slider, self.reset] as [UIView] { view.isHidden = item.shapePicker }
            let columnWidth = (width - 24) / 3
            for (index, button) in self.shapeButtons.enumerated() {
                button.isHidden = !item.shapePicker
                button.frame = CGRect(x: 12 + CGFloat(index) * columnWidth + (columnWidth - cardSide) / 2, y: 12, width: cardSide, height: cardSide)
                button.backgroundColor = item.theme.list.blocksBackgroundColor
                button.layer.borderWidth = index == item.shape ? 2 : 0
                button.layer.borderColor = accent.cgColor
                button.accessibilityTraits = index == item.shape ? [.button, .selected] : .button
                self.shapeSamples[index].frame = button.bounds.insetBy(dx: 10, dy: 10)
                self.shapeSamples[index].backgroundColor = item.theme.list.itemSecondaryTextColor.withAlphaComponent(0.25)
                let label = self.shapeLabels[index]
                label.isHidden = !item.shapePicker
                label.frame = CGRect(x: 12 + CGFloat(index) * columnWidth, y: cardSide + 20, width: columnWidth, height: 22)
                label.textColor = index == item.shape ? accent : item.theme.list.itemPrimaryTextColor
            }
        })
    }

    @objc private func sizeChanged() {
        guard let item else { return }
        let size = min(20, max(1, Int(slider.value.rounded())))
        if size != item.size { item.updated("stickerSize:\(size)") }
    }
    @objc private func resetPressed() { item?.updated("resetStickerAppearance") }
    @objc private func shapePressed(_ sender: UIButton) { item?.updated("stickerShape:\(sender.tag)") }
}
