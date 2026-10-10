import UIKit
import AsyncDisplayKit
import Display
import AppBundle
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import DGSimpleSettings

final class DGIslandStyleItem: ListViewItem, ItemListItem {
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
            let node = DGIslandStyleItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in apply() }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? DGIslandStyleItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class DGIslandStyleItemNode: ListViewItemNode {
    // A grid of three cards per row, one per DGSimpleSettings.appMarks island: a 52 pt card, its caption below,
    // 14 pt between rows.
    private static let columns = 3
    private static let topInset: CGFloat = 14.0
    private static let rowHeight: CGFloat = 90.0
    private static var contentHeight: CGFloat {
        let rows = (DGSimpleSettings.appMarks.count + DGIslandStyleItemNode.columns - 1) / DGIslandStyleItemNode.columns
        return DGIslandStyleItemNode.topInset + CGFloat(rows) * DGIslandStyleItemNode.rowHeight
    }

    private var item: DGIslandStyleItem?
    private var params: ListViewItemLayoutParams?
    private var neighbors: ItemListNeighbors?
    // Holds the whole block and clips it to the row's apparent height: the list grows and collapses the row when
    // «Остров как у иконки» is switched, and the grid would otherwise be drawn at full height over the icons below.
    private let containerView = UIView()
    private let cornersView = UIImageView()
    private var buttons: [UIButton] = []
    private var imageViews: [UIImageView] = []
    private var captions: [UILabel] = []

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.containerView.clipsToBounds = true
        self.view.addSubview(self.containerView)
        self.cornersView.isUserInteractionEnabled = false
        self.containerView.addSubview(self.cornersView)
        // One card per island, drawn as the island itself.
        for (index, mark) in DGSimpleSettings.appMarks.enumerated() {
            let title = mark.title
            let button = UIButton(type: .custom)
            button.tag = index
            button.layer.cornerRadius = 14.0
            button.layer.borderWidth = 2.0
            button.accessibilityLabel = title
            button.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
            self.containerView.addSubview(button)
            self.buttons.append(button)

            let imageView = UIImageView(image: UIImage(bundleImageName: mark.islandAssetName))
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            button.addSubview(imageView)
            self.imageViews.append(imageView)

            let caption = UILabel()
            caption.font = .systemFont(ofSize: 12.0)
            caption.textAlignment = .center
            caption.text = title
            // The card already reads its title to VoiceOver.
            caption.isAccessibilityElement = false
            self.containerView.addSubview(caption)
            self.captions.append(caption)
        }
        self.updateControls()
    }

    func asyncLayout() -> (_ item: DGIslandStyleItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: DGIslandStyleItemNode.contentHeight), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                self?.item = item
                self?.params = params
                self?.neighbors = neighbors
                self?.updateControls()
            })
        }
    }

    private func updateControls() {
        guard let item, let params, let neighbors else { return }
        let theme = item.theme
        self.containerView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.updateContainerFrame(apparentHeight: self.apparentHeight)

        // The block spans the list insets like the other rows; the corner image rounds it like the
        // neighbouring glass rows by painting the page background over its corners.
        let blockX = params.leftInset
        let blockWidth = params.width - params.leftInset - params.rightInset
        var hasTopCorners = true
        var hasBottomCorners = true
        if case .sameSection(false) = neighbors.top {
            hasTopCorners = false
        }
        if case .sameSection(false) = neighbors.bottom {
            hasBottomCorners = false
        }
        self.cornersView.image = itemListHasRoundedBlockLayout(params) ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
        self.cornersView.frame = CGRect(x: blockX, y: 0.0, width: blockWidth, height: DGIslandStyleItemNode.contentHeight)

        let sidePadding: CGFloat = 16.0
        let spacing: CGFloat = 10.0
        let columns = CGFloat(DGIslandStyleItemNode.columns)
        let cardWidth = floor((blockWidth - sidePadding * 2.0 - spacing * (columns - 1.0)) / columns)
        for (index, button) in self.buttons.enumerated() {
            let title = dgLocalized(DGSimpleSettings.appMarks[index].title, languageCode: item.languageCode)
            button.accessibilityLabel = title
            self.captions[index].text = title
            let isSelected = index == item.value
            let x = blockX + sidePadding + CGFloat(index % DGIslandStyleItemNode.columns) * (cardWidth + spacing)
            let y = DGIslandStyleItemNode.topInset + CGFloat(index / DGIslandStyleItemNode.columns) * DGIslandStyleItemNode.rowHeight
            button.frame = CGRect(x: x, y: y, width: cardWidth, height: 52.0)
            button.backgroundColor = theme.list.blocksBackgroundColor
            button.layer.borderColor = (isSelected ? theme.list.itemAccentColor : UIColor.clear).cgColor
            button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
            self.imageViews[index].frame = button.bounds.insetBy(dx: 6.0, dy: 8.0)

            let caption = self.captions[index]
            caption.frame = CGRect(x: x, y: y + 58.0, width: cardWidth, height: 18.0)
            caption.textColor = isSelected ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
        }
    }

    private func updateContainerFrame(apparentHeight: CGFloat) {
        guard let params = self.params else { return }
        let height = min(DGIslandStyleItemNode.contentHeight, max(0.0, apparentHeight - self.insets.top - self.insets.bottom))
        self.containerView.frame = CGRect(x: 0.0, y: 0.0, width: params.width, height: height)
    }

    override func animateFrameTransition(_ progress: CGFloat, _ currentValue: CGFloat) {
        super.animateFrameTransition(progress, currentValue)
        self.updateContainerFrame(apparentHeight: currentValue)
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }

    @objc private func selected(_ sender: UIButton) {
        self.item?.updated(sender.tag)
    }
}
