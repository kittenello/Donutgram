import UIKit
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData

final class ProxyAutoSwitchDelayItem: ListViewItem, ItemListItem {
    static let values: [Int32] = [5, 10, 15, 30, 60]

    let theme: PresentationTheme
    let sectionId: ItemListSectionId
    let value: Int32
    let updated: (Int32) -> Void

    init(theme: PresentationTheme, sectionId: ItemListSectionId, value: Int32, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.sectionId = sectionId
        self.value = value
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ProxyAutoSwitchDelayItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ProxyAutoSwitchDelayItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class ProxyAutoSwitchDelayItemNode: ListViewItemNode {
    private var item: ProxyAutoSwitchDelayItem?
    private let block = UIView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private var slider: UISlider?
    private var tickLabels: [UILabel] = []
    private var layoutWidth: CGFloat = 0.0
    private var leftInset: CGFloat = 0.0
    private var rightInset: CGFloat = 0.0
    private var hasTopCorners = false
    private var hasBottomCorners = false

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.block)
        self.block.isUserInteractionEnabled = false
        self.block.layer.cornerRadius = 22.0
        self.block.clipsToBounds = true
        self.titleLabel.text = "Время ожидания"
        self.titleLabel.font = .systemFont(ofSize: 17.0)
        self.valueLabel.font = .systemFont(ofSize: 15.0)
        self.valueLabel.textAlignment = .right
        self.view.addSubview(self.titleLabel)
        self.view.addSubview(self.valueLabel)

        let slider = UISlider()
        slider.minimumValue = 0.0
        slider.maximumValue = Float(ProxyAutoSwitchDelayItem.values.count - 1)
        if #available(iOS 26.0, *) {
            slider.trackConfiguration = .init(numberOfTicks: ProxyAutoSwitchDelayItem.values.count)
        }
        slider.isContinuous = false
        slider.disablesInteractiveTransitionGestureRecognizer = true
        slider.accessibilityLabel = "Время ожидания"
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        self.view.addSubview(slider)
        self.slider = slider
        for seconds in ProxyAutoSwitchDelayItem.values {
            let label = UILabel()
            label.text = "\(seconds)"
            label.font = .systemFont(ofSize: 13.0)
            label.textAlignment = .center
            self.view.addSubview(label)
            self.tickLabels.append(label)
        }
        self.updateControls()
    }

    func asyncLayout() -> (_ item: ProxyAutoSwitchDelayItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 112.0), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                guard let self else { return }
                self.item = item
                self.layoutWidth = params.width
                self.leftInset = params.leftInset
                self.rightInset = params.rightInset
                if case .sameSection(false) = neighbors.top { self.hasTopCorners = false } else { self.hasTopCorners = true }
                if case .sameSection(false) = neighbors.bottom { self.hasBottomCorners = false } else { self.hasBottomCorners = true }
                self.updateControls()
            })
        }
    }

    private func updateControls() {
        guard let item else { return }
        self.backgroundColor = .clear
        self.block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        var corners: CACornerMask = []
        if self.hasTopCorners { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if self.hasBottomCorners { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        self.block.layer.maskedCorners = corners
        self.block.frame = CGRect(x: self.leftInset, y: 0.0, width: max(0.0, self.layoutWidth - self.leftInset - self.rightInset), height: 112.0)
        let contentX = self.leftInset + 16.0
        let contentWidth = max(0.0, self.layoutWidth - self.leftInset - self.rightInset - 32.0)
        self.titleLabel.textColor = item.theme.list.itemPrimaryTextColor
        self.valueLabel.textColor = item.theme.list.itemSecondaryTextColor
        self.titleLabel.frame = CGRect(x: contentX, y: 10.0, width: max(0.0, contentWidth - 72.0), height: 24.0)
        self.valueLabel.frame = CGRect(x: contentX + contentWidth - 72.0, y: 10.0, width: 72.0, height: 24.0)
        self.slider?.frame = CGRect(x: contentX, y: 40.0, width: contentWidth, height: 38.0)
        self.slider?.minimumTrackTintColor = item.theme.list.itemAccentColor
        self.slider?.maximumTrackTintColor = item.theme.list.itemSecondaryTextColor.withAlphaComponent(0.4)
        let index = ProxyAutoSwitchDelayItem.values.firstIndex(of: item.value) ?? 1
        self.slider?.value = Float(index)
        self.updateValue(index: index)
        for (i, label) in self.tickLabels.enumerated() {
            let fraction = CGFloat(i) / CGFloat(ProxyAutoSwitchDelayItem.values.count - 1)
            // Match the thumb centers, rather than the outer edges of the slider.
            let x = contentX + 14.0 + fraction * max(0.0, contentWidth - 28.0)
            label.frame = CGRect(x: x - 16.0, y: 82.0, width: 32.0, height: 20.0)
        }
    }

    private func updateValue(index: Int) {
        guard let item else { return }
        let text = "\(ProxyAutoSwitchDelayItem.values[index]) сек."
        self.valueLabel.text = text
        self.slider?.accessibilityValue = text
        for (i, label) in self.tickLabels.enumerated() {
            label.textColor = i == index ? item.theme.list.itemAccentColor : item.theme.list.itemSecondaryTextColor
        }
    }

    @objc private func valueChanged() {
        guard let slider else { return }
        let index = min(max(Int(slider.value.rounded()), 0), ProxyAutoSwitchDelayItem.values.count - 1)
        slider.value = Float(index)
        self.updateValue(index: index)
        self.item?.updated(ProxyAutoSwitchDelayItem.values[index])
    }
}
