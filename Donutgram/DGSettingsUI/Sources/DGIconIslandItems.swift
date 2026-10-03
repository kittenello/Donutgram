import UIKit
import AsyncDisplayKit
import Display
import AppBundle
import AccountContext
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import SettingsUI
import DGSimpleSettings

/// Shows the island picked on the «Иконка и остров» page at once. AppDelegate.updateDonutgramBadge does the same
/// on launch and after every icon change.
func dgApplyIslandBadge(context: AccountContext) {
    let index = DGSimpleSettings.shared.islandMarkIndex(iconName: context.sharedContext.applicationBindings.getAlternateIconName())
    if let image = UIImage(bundleImageName: DGSimpleSettings.appMarks[index].islandAssetName) {
        context.sharedContext.mainWindow?.badgeView.image = image
    }
}

/// «Предпросмотр» on «Иконка и остров»: a status bar with the current island, and the current app icon under it.
final class DGIconIslandPreviewItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let languageCode: String
    let sectionId: ItemListSectionId
    let icon: DGSimpleSettings.AppMark
    let island: DGSimpleSettings.AppMark

    init(theme: PresentationTheme, languageCode: String, sectionId: ItemListSectionId, icon: DGSimpleSettings.AppMark, island: DGSimpleSettings.AppMark) {
        self.theme = theme
        self.languageCode = languageCode
        self.sectionId = sectionId
        self.icon = icon
        self.island = island
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = DGIconIslandPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in apply() }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? DGIconIslandPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class DGIconIslandPreviewItemNode: ListViewItemNode {
    private static let contentHeight: CGFloat = 170.0

    private var item: DGIconIslandPreviewItem?
    private var params: ListViewItemLayoutParams?
    private var neighbors: ItemListNeighbors?
    private let cornersView = UIImageView()
    private let stripView = UIView()
    private let timeLabel = UILabel()
    private let islandView = UIImageView()
    private let batteryView = UIImageView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.cornersView.isUserInteractionEnabled = false
        self.view.addSubview(self.cornersView)

        self.stripView.layer.cornerRadius = 12.0
        self.stripView.layer.cornerCurve = .continuous
        self.view.addSubview(self.stripView)
        self.timeLabel.text = "9:41"
        self.timeLabel.font = .systemFont(ofSize: 15.0, weight: .semibold)
        self.stripView.addSubview(self.timeLabel)
        self.islandView.contentMode = .scaleAspectFit
        self.stripView.addSubview(self.islandView)
        self.batteryView.contentMode = .scaleAspectFit
        self.batteryView.image = UIImage(systemName: "battery.100", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .regular))
        self.stripView.addSubview(self.batteryView)

        self.iconView.layer.cornerRadius = 60.0 * 0.2237
        self.iconView.layer.cornerCurve = .continuous
        self.iconView.clipsToBounds = true
        self.view.addSubview(self.iconView)
        self.titleLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.view.addSubview(self.titleLabel)

        // One element for VoiceOver instead of the time, the battery and two images.
        self.view.isAccessibilityElement = true
        self.updateControls()
    }

    func asyncLayout() -> (_ item: DGIconIslandPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: DGIconIslandPreviewItemNode.contentHeight), insets: itemListNeighborsGroupedInsets(neighbors, params))
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
        self.backgroundColor = theme.list.itemBlocksBackgroundColor

        // Rounded like the neighbouring glass rows, as DGIslandStyleItem does.
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
        self.cornersView.frame = CGRect(x: blockX, y: 0.0, width: blockWidth, height: DGIconIslandPreviewItemNode.contentHeight)

        // A status bar, 93x22 pt island in the middle like on the phone.
        self.stripView.frame = CGRect(x: blockX + 16.0, y: 16.0, width: blockWidth - 32.0, height: 40.0)
        self.stripView.backgroundColor = theme.list.blocksBackgroundColor
        self.timeLabel.textColor = theme.list.itemPrimaryTextColor
        self.timeLabel.frame = CGRect(x: 16.0, y: 10.0, width: 60.0, height: 20.0)
        self.islandView.image = UIImage(bundleImageName: item.island.islandAssetName)
        self.islandView.frame = CGRect(x: floor((self.stripView.bounds.width - 93.0) / 2.0), y: 9.0, width: 93.0, height: 22.0)
        self.batteryView.tintColor = theme.list.itemPrimaryTextColor
        self.batteryView.frame = CGRect(x: self.stripView.bounds.width - 16.0 - 28.0, y: 10.0, width: 28.0, height: 20.0)

        self.iconView.image = donutgramAppIconThumbnail(iconName: item.icon.iconName, size: 60.0)
        self.iconView.frame = CGRect(x: blockX + floor((blockWidth - 60.0) / 2.0), y: 72.0, width: 60.0, height: 60.0)
        self.titleLabel.text = dgLocalized(item.icon.title, languageCode: item.languageCode)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.titleLabel.frame = CGRect(x: blockX + 16.0, y: 138.0, width: blockWidth - 32.0, height: 18.0)

        self.view.accessibilityLabel = dgLocalized("Иконка", languageCode: item.languageCode) + ": " + dgLocalized(item.icon.title, languageCode: item.languageCode) + ", " + dgLocalized("Остров", languageCode: item.languageCode) + ": " + dgLocalized(item.island.title, languageCode: item.languageCode)
    }
}
