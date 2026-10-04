import UIKit
import DGSimpleSettings
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData

final class DGSpeedSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let languageCode: String
    let sectionId: ItemListSectionId
    let value: Int
    let updated: (Int) -> Void

    init(theme: PresentationTheme, languageCode: String, sectionId: ItemListSectionId, value: Int, updated: @escaping (Int) -> Void) {
        self.theme = theme
        self.languageCode = languageCode
        self.sectionId = sectionId
        self.value = value
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = DGSpeedSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? DGSpeedSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

final class DGSpeedSliderItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag? { DGSettingItemTag(key: "downloadAcceleration") }
    private var item: DGSpeedSliderItem?
    private var slider: UISlider?
    private var labels: [UILabel] = []
    private var layoutWidth: CGFloat = 0
    private var leftInset: CGFloat = 0
    private var rightInset: CGFloat = 0
    private var hasTopCorners = true
    private var hasBottomCorners = false
    private let blockBackground = UIView()

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.blockBackground)
        self.blockBackground.isUserInteractionEnabled = false
        self.blockBackground.layer.cornerRadius = 22.0
        self.blockBackground.clipsToBounds = true
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 2
        slider.isContinuous = false
        slider.disablesInteractiveTransitionGestureRecognizer = true
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        self.view.addSubview(slider)
        self.slider = slider
        for title in ["Откл.", "Быстро", "Ультра"] {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 14)
            self.view.addSubview(label)
            self.labels.append(label)
        }
        updateControls()
    }

    func displayHighlight() {
        guard let item else { return }
        dgDisplayHighlight(in: self.blockBackground, theme: item.theme)
    }

    func asyncLayout() -> (_ item: DGSpeedSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 86), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                self?.item = item
                self?.layoutWidth = params.width
                self?.leftInset = params.leftInset
                self?.rightInset = params.rightInset
                if case .sameSection(false) = neighbors.top {
                    self?.hasTopCorners = false
                } else {
                    self?.hasTopCorners = true
                }
                if case .sameSection(false) = neighbors.bottom {
                    self?.hasBottomCorners = false
                } else {
                    self?.hasBottomCorners = true
                }
                self?.updateControls()
            })
        }
    }

    private func updateControls() {
        guard let item else { return }
        self.backgroundColor = .clear
        self.blockBackground.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        var corners: CACornerMask = []
        if self.hasTopCorners {
            corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }
        if self.hasBottomCorners {
            corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        self.blockBackground.layer.maskedCorners = corners
        self.blockBackground.frame = CGRect(x: self.leftInset, y: 0, width: max(0, self.layoutWidth - self.leftInset - self.rightInset), height: 86)
        slider?.minimumTrackTintColor = item.theme.list.itemAccentColor
        slider?.maximumTrackTintColor = item.theme.list.itemSecondaryTextColor.withAlphaComponent(0.4)
        slider?.value = Float(item.value)
        slider?.frame = CGRect(x: leftInset + 12, y: 38, width: max(0, layoutWidth - leftInset - rightInset - 24), height: 38)
        for (index, label) in labels.enumerated() {
            label.text = dgLocalized(["Откл.", "Быстро", "Ультра"][index], languageCode: item.languageCode)
            label.textColor = index == item.value ? item.theme.list.itemAccentColor : item.theme.list.itemSecondaryTextColor
            let x = index == 0 ? leftInset + 12 : (index == 1 ? layoutWidth / 2 - 40 : layoutWidth - rightInset - 92)
            label.frame = CGRect(x: x, y: 10, width: 80, height: 22)
            label.textAlignment = index == 0 ? .left : (index == 1 ? .center : .right)
        }
    }

    @objc private func valueChanged() {
        guard let slider else { return }
        let value = min(max(Int(slider.value.rounded()), 0), 2)
        slider.value = Float(value)
        item?.updated(value)
    }
}
