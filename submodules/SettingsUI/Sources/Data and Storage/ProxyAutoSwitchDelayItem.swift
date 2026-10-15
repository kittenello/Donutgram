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

// VoiceOver steps the slider by a tenth of its range, which the rounding in valueChanged would undo,
// so increment and decrement move by one value.
private final class ProxyAutoSwitchDelaySlider: UISlider {
    override func accessibilityIncrement() {
        self.step(by: 1.0)
    }

    override func accessibilityDecrement() {
        self.step(by: -1.0)
    }

    private func step(by delta: Float) {
        self.value = min(max(self.value.rounded() + delta, self.minimumValue), self.maximumValue)
        self.sendActions(for: .valueChanged)
    }
}

private final class ProxyAutoSwitchDelayItemNode: ListViewItemNode {
    private var item: ProxyAutoSwitchDelayItem?
    // Views are created in didLoad: the node itself may be created off the main thread.
    private var block: UIView?
    private var separator: UIView?
    private var titleLabel: UILabel?
    private var valueLabel: UILabel?
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
        let block = UIView()
        block.isUserInteractionEnabled = false
        block.layer.cornerRadius = 22.0
        block.clipsToBounds = true
        self.view.addSubview(block)
        self.block = block

        let separator = UIView()
        separator.isUserInteractionEnabled = false
        self.view.addSubview(separator)
        self.separator = separator

        let titleLabel = UILabel()
        titleLabel.text = "Время ожидания"
        titleLabel.font = .systemFont(ofSize: 17.0)
        self.view.addSubview(titleLabel)
        self.titleLabel = titleLabel

        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 15.0)
        valueLabel.textAlignment = .right
        self.view.addSubview(valueLabel)
        self.valueLabel = valueLabel

        let slider = ProxyAutoSwitchDelaySlider()
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
        guard let item, let block = self.block, let separator = self.separator, let titleLabel = self.titleLabel, let valueLabel = self.valueLabel, let slider = self.slider else { return }
        self.backgroundColor = .clear
        block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        var corners: CACornerMask = []
        if self.hasTopCorners { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if self.hasBottomCorners { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        block.layer.maskedCorners = corners
        block.frame = CGRect(x: self.leftInset, y: 0.0, width: max(0.0, self.layoutWidth - self.leftInset - self.rightInset), height: 112.0)
        let contentX = self.leftInset + 16.0
        let contentWidth = max(0.0, self.layoutWidth - self.leftInset - self.rightInset - 32.0)

        // A row followed by another row of the block draws the line between them, inset as in the glass rows.
        separator.isHidden = self.hasBottomCorners
        separator.backgroundColor = item.theme.list.itemBlocksSeparatorColor
        separator.frame = CGRect(x: contentX, y: 112.0 - UIScreenPixel, width: contentWidth, height: UIScreenPixel)

        titleLabel.textColor = item.theme.list.itemPrimaryTextColor
        valueLabel.textColor = item.theme.list.itemSecondaryTextColor
        titleLabel.frame = CGRect(x: contentX, y: 10.0, width: max(0.0, contentWidth - 72.0), height: 24.0)
        valueLabel.frame = CGRect(x: contentX + contentWidth - 72.0, y: 10.0, width: 72.0, height: 24.0)
        slider.frame = CGRect(x: contentX, y: 40.0, width: contentWidth, height: 38.0)
        slider.minimumTrackTintColor = item.theme.list.itemAccentColor
        slider.maximumTrackTintColor = item.theme.list.itemSecondaryTextColor.withAlphaComponent(0.4)
        let index = ProxyAutoSwitchDelayItem.values.firstIndex(of: item.value) ?? 1
        slider.value = Float(index)
        self.updateValue(index: index)
        // Each label sits under the thumb center for its value, as the slider itself computes it,
        // so the labels follow the thumb and track of every iOS version.
        let trackRect = slider.trackRect(forBounds: slider.bounds)
        for (i, label) in self.tickLabels.enumerated() {
            let thumbRect = slider.thumbRect(forBounds: slider.bounds, trackRect: trackRect, value: Float(i))
            let x = slider.frame.minX + thumbRect.midX
            label.frame = CGRect(x: x - 16.0, y: 82.0, width: 32.0, height: 20.0)
        }
    }

    private func updateValue(index: Int) {
        guard let item else { return }
        let text = "\(ProxyAutoSwitchDelayItem.values[index]) сек."
        self.valueLabel?.text = text
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
