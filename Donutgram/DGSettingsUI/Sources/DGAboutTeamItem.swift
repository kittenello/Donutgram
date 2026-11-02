import UIKit
import AsyncDisplayKit
import Display
import AppBundle
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import DGSimpleSettings

/// The team at the top of «О Donutgram», drawn like a Telegram profile: both avatars blurred into the card's background,
/// the two avatars overlapping, the nicknames, and buttons for the channel and the source code.
final class DGAboutTeamItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let languageCode: String
    let sectionId: ItemListSectionId
    let openChannel: () -> Void
    let openSourceCode: () -> Void

    init(theme: PresentationTheme, languageCode: String, sectionId: ItemListSectionId, openChannel: @escaping () -> Void, openSourceCode: @escaping () -> Void) {
        self.theme = theme
        self.languageCode = languageCode
        self.sectionId = sectionId
        self.openChannel = openChannel
        self.openSourceCode = openSourceCode
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = DGAboutTeamItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in apply() }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? DGAboutTeamItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class DGAboutTeamItemNode: ListViewItemNode {
    // 24 pt above the avatars, the two lines of text, then the 62 pt buttons and 16 pt below them.
    private static let contentHeight: CGFloat = 278.0
    private static let avatarSize: CGFloat = 96.0
    private static let avatarOverlap: CGFloat = 22.0

    private var item: DGAboutTeamItem?
    private var params: ListViewItemLayoutParams?
    private var neighbors: ItemListNeighbors?
    private let backgroundView = UIImageView()
    // мр пончик, then якиями: the first one is drawn over the second.
    private let avatarViews = [UIImageView(), UIImageView()]
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let channelButton = DGAboutTeamButton()
    private let sourceCodeButton = DGAboutTeamButton()
    private let cornersView = UIImageView()

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        // The avatars of both, blurred and darkened so the white text reads on it, in the same colours for both themes.
        self.backgroundView.image = UIImage(bundleImageName: "Donutgram/AboutTeamBanner")
        self.backgroundView.contentMode = .scaleAspectFill
        self.backgroundView.clipsToBounds = true
        self.view.addSubview(self.backgroundView)

        for (imageView, name) in zip(self.avatarViews, ["Donutgram/AboutTeamPonchik", "Donutgram/AboutTeamYakiyami"]).reversed() {
            imageView.image = UIImage(bundleImageName: name)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = DGAboutTeamItemNode.avatarSize / 2.0
            imageView.layer.borderWidth = 3.5
            imageView.layer.borderColor = UIColor(white: 1.0, alpha: 0.92).cgColor
            imageView.isAccessibilityElement = false
            self.view.addSubview(imageView)
        }

        self.titleLabel.font = .systemFont(ofSize: 22.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.adjustsFontSizeToFitWidth = true
        self.titleLabel.minimumScaleFactor = 0.8
        self.view.addSubview(self.titleLabel)
        self.subtitleLabel.font = .systemFont(ofSize: 15.0, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.75)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.isAccessibilityElement = false
        self.view.addSubview(self.subtitleLabel)

        let symbol = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .semibold)
        self.channelButton.iconView.image = UIImage(systemName: "paperplane.fill", withConfiguration: symbol)
        self.channelButton.addTarget(self, action: #selector(self.channelPressed), for: .touchUpInside)
        self.view.addSubview(self.channelButton)
        self.sourceCodeButton.iconView.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right", withConfiguration: symbol)
        self.sourceCodeButton.titleLabel.text = "GitHub"
        self.sourceCodeButton.accessibilityLabel = "GitHub"
        self.sourceCodeButton.addTarget(self, action: #selector(self.sourceCodePressed), for: .touchUpInside)
        self.view.addSubview(self.sourceCodeButton)

        // Rounds the card like the neighbouring glass rows by painting the page background over its corners, so it
        // goes over the background image.
        self.cornersView.isUserInteractionEnabled = false
        self.view.addSubview(self.cornersView)
        self.updateControls()
    }

    func asyncLayout() -> (_ item: DGAboutTeamItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: DGAboutTeamItemNode.contentHeight), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                self?.item = item
                self?.params = params
                self?.neighbors = neighbors
                self?.updateControls()
            })
        }
    }

    private func updateControls() {
        guard let item, let params, let neighbors, self.isNodeLoaded else { return }
        let theme = item.theme
        let height = DGAboutTeamItemNode.contentHeight
        let blockX = params.leftInset
        let blockWidth = params.width - params.leftInset - params.rightInset
        self.backgroundView.frame = CGRect(x: blockX, y: 0.0, width: blockWidth, height: height)

        var hasTopCorners = true
        var hasBottomCorners = true
        if case .sameSection(false) = neighbors.top {
            hasTopCorners = false
        }
        if case .sameSection(false) = neighbors.bottom {
            hasBottomCorners = false
        }
        self.cornersView.image = itemListHasRoundedBlockLayout(params) ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
        self.cornersView.frame = CGRect(x: blockX, y: 0.0, width: blockWidth, height: height)

        let size = DGAboutTeamItemNode.avatarSize
        let pairX = blockX + floor((blockWidth - (size * 2.0 - DGAboutTeamItemNode.avatarOverlap)) / 2.0)
        self.avatarViews[0].frame = CGRect(x: pairX, y: 24.0, width: size, height: size)
        self.avatarViews[1].frame = CGRect(x: pairX + size - DGAboutTeamItemNode.avatarOverlap, y: 24.0, width: size, height: size)

        let title = dgLocalized("мр пончик и якиями", languageCode: item.languageCode)
        let subtitle = dgLocalized("команда Donutgram", languageCode: item.languageCode)
        self.titleLabel.text = title
        self.titleLabel.frame = CGRect(x: blockX + 16.0, y: 132.0, width: blockWidth - 32.0, height: 27.0)
        self.titleLabel.accessibilityLabel = title + ", " + subtitle
        self.subtitleLabel.text = subtitle
        self.subtitleLabel.frame = CGRect(x: blockX + 16.0, y: 161.0, width: blockWidth - 32.0, height: 20.0)

        let channel = dgLocalized("Канал", languageCode: item.languageCode)
        self.channelButton.titleLabel.text = channel
        self.channelButton.accessibilityLabel = channel
        let buttonWidth = floor((blockWidth - 32.0 - 10.0) / 2.0)
        self.channelButton.frame = CGRect(x: blockX + 16.0, y: 200.0, width: buttonWidth, height: 62.0)
        self.sourceCodeButton.frame = CGRect(x: blockX + blockWidth - 16.0 - buttonWidth, y: 200.0, width: buttonWidth, height: 62.0)
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }

    @objc private func channelPressed() {
        self.item?.openChannel()
    }

    @objc private func sourceCodePressed() {
        self.item?.openSourceCode()
    }
}

/// A glass button of the card, as on a Telegram profile: the icon over its title, in white.
private final class DGAboutTeamButton: UIControl {
    let iconView = UIImageView()
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(white: 1.0, alpha: 0.2)
        self.layer.cornerRadius = 16.0
        self.layer.cornerCurve = .continuous
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.iconView.tintColor = .white
        self.iconView.contentMode = .center
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)
        self.titleLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.iconView.frame = CGRect(x: 0.0, y: 9.0, width: self.bounds.width, height: 26.0)
        self.titleLabel.frame = CGRect(x: 4.0, y: 37.0, width: self.bounds.width - 8.0, height: 17.0)
    }
}
