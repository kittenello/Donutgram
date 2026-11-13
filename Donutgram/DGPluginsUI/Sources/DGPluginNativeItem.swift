import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData

final class DGPluginNativeItem: ListViewItem, ItemListItem {
    enum Content {
        case card(UIImage, String, String, String)
        case number(String, Double, Double, Double, Double, Bool)
        case multiline(String, String, Int)
        case image(UIImage, String)
        case markdown(String)
    }
    let theme: PresentationTheme
    let sectionId: ItemListSectionId
    let content: Content
    let scale: CGFloat
    let accentColor: UIColor?
    let numberUpdated: (Double) -> Void
    let textUpdated: (String) -> Void

    init(theme: PresentationTheme, sectionId: ItemListSectionId, content: Content, scale: CGFloat = 1, accentColor: UIColor? = nil, numberUpdated: @escaping (Double) -> Void = { _ in }, textUpdated: @escaping (String) -> Void = { _ in }) {
        self.theme = theme
        self.sectionId = sectionId
        self.content = content
        self.scale = min(2, max(0.8, scale))
        self.accentColor = accentColor
        self.numberUpdated = numberUpdated
        self.textUpdated = textUpdated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = DGPluginNativeItemNode()
            let calculate = node.asyncLayout()
            async {
                let (layout, apply) = calculate(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
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
            guard let node = node() as? DGPluginNativeItemNode else { return }
            let layout = node.asyncLayout()
            async {
                let (result, apply) = layout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                Queue.mainQueue().async { completion(result, { _ in apply() }) }
            }
        }
    }

    static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        return ceil(text.boundingRect(with: CGSize(width: max(1, width), height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    func height(width: CGFloat) -> CGFloat {
        let inner = max(1, width - 32)
        switch self.content {
        case let .card(_, title, subtitle, description):
            return 136 + Self.textHeight(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 22 * self.scale, weight: .semibold)]), width: inner) + Self.textHeight(NSAttributedString(string: subtitle, attributes: [.font: UIFont.systemFont(ofSize: 15 * self.scale)]), width: inner) + Self.textHeight(NSAttributedString(string: description, attributes: [.font: UIFont.systemFont(ofSize: 16 * self.scale)]), width: inner)
        case let .number(title, value, _, _, _, slider):
            let titleHeight = Self.textHeight(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 16 * self.scale)]), width: max(1, inner - (slider ? 0 : 112)))
            let valueHeight = Self.textHeight(NSAttributedString(string: String(format: "%g", value), attributes: [.font: UIFont.systemFont(ofSize: 15 * self.scale)]), width: inner)
            return max(72, titleHeight + valueHeight + (slider ? 72 : 30))
        case let .multiline(title, _, _): return 156 + Self.textHeight(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 16 * self.scale)]), width: inner)
        case let .image(image, title):
            let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
            let titleHeight = title.isEmpty ? 0 : Self.textHeight(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 15 * self.scale)]), width: inner) + 8
            return min(220, inner * aspect) + 32 + titleHeight
        case let .markdown(text):
            return Self.textHeight(dgPluginMarkdown(text, color: self.theme.list.itemPrimaryTextColor, scale: self.scale), width: inner) + 32
        }
    }
}

private final class DGPluginNativeSlider: UISlider {
    var stepSize: Float = 1
    override func accessibilityIncrement() { self.value = min(self.maximumValue, self.value + self.stepSize); self.sendActions(for: .valueChanged) }
    override func accessibilityDecrement() { self.value = max(self.minimumValue, self.value - self.stepSize); self.sendActions(for: .valueChanged) }
}

private final class DGPluginNativeItemNode: ListViewItemNode, UITextViewDelegate {
    private var item: DGPluginNativeItem?
    private var params: ListViewItemLayoutParams?
    private var neighbors: ItemListNeighbors?
    private let block = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let imageView = UIImageView()
    private let slider = DGPluginNativeSlider()
    private let stepper = UIStepper()
    private let textView = UITextView()

    init() { super.init(layerBacked: false) }

    override func didLoad() {
        super.didLoad()
        self.block.layer.cornerRadius = 22
        self.block.clipsToBounds = true
        self.view.addSubview(self.block)
        for label in [self.titleLabel, self.subtitleLabel, self.bodyLabel] { label.numberOfLines = 0; label.isAccessibilityElement = true; self.block.addSubview(label) }
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerRadius = 18
        self.block.addSubview(self.imageView)
        self.slider.isContinuous = false
        self.slider.disablesInteractiveTransitionGestureRecognizer = true
        self.slider.addTarget(self, action: #selector(numberChanged), for: .valueChanged)
        self.stepper.addTarget(self, action: #selector(numberChanged), for: .valueChanged)
        self.block.addSubview(self.slider)
        self.block.addSubview(self.stepper)
        self.textView.delegate = self
        self.textView.isScrollEnabled = true
        self.textView.font = .systemFont(ofSize: 16)
        self.textView.autocorrectionType = .no
        self.textView.dataDetectorTypes = []
        self.block.addSubview(self.textView)
        self.apply()
    }

    func asyncLayout() -> (DGPluginNativeItem, ListViewItemLayoutParams, ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let height = item.height(width: params.width - params.leftInset - params.rightInset)
            return (ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: itemListNeighborsGroupedInsets(neighbors, params)), { [weak self] in
                self?.item = item
                self?.params = params
                self?.neighbors = neighbors
                self?.apply()
            })
        }
    }

    private func apply() {
        guard let item, let params, let neighbors, self.isNodeLoaded else { return }
        let width = max(1, params.width - params.leftInset - params.rightInset)
        let height = item.height(width: width)
        self.block.frame = CGRect(x: params.leftInset, y: 0, width: width, height: height)
        self.block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        if case .card = item.content { self.block.backgroundColor = item.theme.list.blocksBackgroundColor }
        var corners: CACornerMask = []
        if case .sameSection(false) = neighbors.top {} else { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if case .sameSection(false) = neighbors.bottom {} else { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        self.block.layer.maskedCorners = corners
        let views: [UIView] = [self.titleLabel, self.subtitleLabel, self.bodyLabel, self.imageView, self.slider, self.stepper, self.textView]
        for view in views { view.isHidden = true }
        for label in [self.titleLabel, self.subtitleLabel, self.bodyLabel] { label.textAlignment = .natural; label.textColor = item.theme.list.itemPrimaryTextColor; label.attributedText = nil }
        self.titleLabel.font = .systemFont(ofSize: 16 * item.scale)
        self.subtitleLabel.font = .systemFont(ofSize: 15 * item.scale)
        self.subtitleLabel.textColor = item.theme.list.itemSecondaryTextColor
        self.bodyLabel.font = .systemFont(ofSize: 16 * item.scale)
        let inner = max(1, width - 32)
        func label(_ label: UILabel, _ text: String, y: CGFloat) -> CGFloat {
            label.isHidden = false
            label.text = text
            let size = label.sizeThatFits(CGSize(width: inner, height: 100000))
            label.frame = CGRect(x: 16, y: y, width: inner, height: ceil(size.height))
            return label.frame.maxY
        }
        switch item.content {
        case let .card(image, title, subtitle, description):
            self.imageView.isHidden = false
            self.imageView.image = image
            self.imageView.frame = CGRect(x: (width - 68) / 2, y: 16, width: 68, height: 68)
            self.titleLabel.font = .systemFont(ofSize: 22 * item.scale, weight: .semibold)
            self.titleLabel.textAlignment = .center
            self.subtitleLabel.textAlignment = .center
            let titleEnd = label(self.titleLabel, title, y: 100)
            let subtitleEnd = label(self.subtitleLabel, subtitle, y: titleEnd + 6)
            let _ = label(self.bodyLabel, description, y: subtitleEnd + 16)
        case let .number(title, value, minimum, maximum, step, useSlider):
            self.titleLabel.isHidden = false
            self.titleLabel.text = title
            let titleWidth = max(1, inner - (useSlider ? 0 : 112))
            let titleHeight = self.titleLabel.sizeThatFits(CGSize(width: titleWidth, height: 100000)).height
            self.titleLabel.frame = CGRect(x: 16, y: 12, width: titleWidth, height: ceil(titleHeight))
            let valueEnd = label(self.subtitleLabel, String(format: "%g", value), y: self.titleLabel.frame.maxY + 6)
            if useSlider {
                self.slider.isHidden = false
                self.slider.minimumValue = 0
                self.slider.maximumValue = 1
                self.slider.stepSize = Float(step / (maximum - minimum))
                self.slider.value = Float((value - minimum) / (maximum - minimum))
                self.slider.minimumTrackTintColor = item.accentColor ?? item.theme.list.itemAccentColor
                self.slider.frame = CGRect(x: 16, y: valueEnd + 8, width: inner, height: 34)
                self.slider.accessibilityLabel = title
                self.slider.accessibilityValue = String(format: "%g", value)
            } else {
                self.stepper.isHidden = false
                self.stepper.minimumValue = minimum
                self.stepper.maximumValue = maximum
                self.stepper.stepValue = step
                self.stepper.value = value
                self.stepper.tintColor = item.accentColor ?? item.theme.list.itemAccentColor
                self.stepper.frame = CGRect(x: width - 110, y: 16, width: 94, height: 32)
                self.stepper.accessibilityLabel = title
                self.stepper.accessibilityValue = String(format: "%g", value)
            }
        case let .multiline(title, text, _):
            let titleEnd = label(self.titleLabel, title, y: 12)
            self.textView.isHidden = false
            self.textView.textColor = item.theme.list.itemPrimaryTextColor
            self.textView.tintColor = item.accentColor ?? item.theme.list.itemAccentColor
            self.textView.backgroundColor = .clear
            self.textView.accessibilityLabel = title
            self.textView.font = .systemFont(ofSize: 16 * item.scale)
            self.textView.frame = CGRect(x: 12, y: titleEnd + 8, width: max(1, width - 24), height: max(44, height - titleEnd - 20))
            if self.textView.text != text { self.textView.text = text }
        case let .image(image, title):
            self.imageView.isHidden = false
            self.imageView.image = image
            self.imageView.accessibilityLabel = title
            self.imageView.isAccessibilityElement = !title.isEmpty
            let captionHeight = title.isEmpty ? 0 : DGPluginNativeItem.textHeight(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 15 * item.scale)]), width: inner) + 8
            self.imageView.frame = CGRect(x: 16, y: 16, width: inner, height: height - 32 - captionHeight)
            if !title.isEmpty { let _ = label(self.subtitleLabel, title, y: self.imageView.frame.maxY + 8) }
        case let .markdown(text):
            self.bodyLabel.isHidden = false
            self.bodyLabel.attributedText = dgPluginMarkdown(text, color: item.theme.list.itemPrimaryTextColor, scale: item.scale)
            self.bodyLabel.frame = CGRect(x: 16, y: 16, width: inner, height: height - 32)
        }
    }

    @objc private func numberChanged(_ sender: UIControl) {
        guard let item, case let .number(_, _, minimum, maximum, step, _) = item.content else { return }
        let fromSlider = sender === self.slider
        let raw = fromSlider ? minimum + Double(self.slider.value) * (maximum - minimum) : self.stepper.value
        let value = dgPluginNumericControlValue(raw, minimum: minimum, maximum: maximum, step: step)
        self.slider.value = Float((value - minimum) / (maximum - minimum))
        self.stepper.value = value
        self.subtitleLabel.text = String(format: "%g", value)
        item.numberUpdated(value)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let item, case let .multiline(_, _, limit) = item.content else { return false }
        let current = textView.text as NSString
        return range.location >= 0 && range.length >= 0 && range.location <= current.length && range.length <= current.length - range.location && current.length - range.length + text.utf16.count <= limit
    }

    func textViewDidChange(_ textView: UITextView) { self.item?.textUpdated(textView.text) }
}

func dgPluginMarkdown(_ source: String, color: UIColor, scale: CGFloat = 1) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    for run in dgPluginMarkdownRuns(source) {
        let font: UIFont
        switch run.style {
        case .code: font = .monospacedSystemFont(ofSize: 15 * scale, weight: .regular)
        case .bold: font = .systemFont(ofSize: 16 * scale, weight: .semibold)
        case .italic: font = .italicSystemFont(ofSize: 16 * scale)
        case .heading: font = .systemFont(ofSize: 19 * scale, weight: .semibold)
        case .body: font = .systemFont(ofSize: 16 * scale)
        }
        result.append(NSAttributedString(string: run.text, attributes: [.font: font, .foregroundColor: color]))
    }
    return result
}
