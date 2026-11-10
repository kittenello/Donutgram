import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import ItemListUI
import TelegramPresentationData
import DGPluginModel
import DGPluginInstaller
import DGPluginHost
import UndoUI

final class DGPluginInstallController: ViewController {
    private let context: AccountContext
    private let package: DGVerifiedPluginPackage
    private let manager: DGPluginManager
    private let backdrop = UIControl()
    private let sheet = UIView()
    private let scroll = UIScrollView()
    private let grabber = UIView()
    private let typeLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let authorLabel = UILabel()
    private let descriptionBackground = UIView()
    private let descriptionLabel = UILabel()
    private let enabledLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let installButton = UIButton(type: .system)
    private let progress: UIActivityIndicatorView = {
        if #available(iOS 13.0, *) { return UIActivityIndicatorView(style: .medium) }
        return UIActivityIndicatorView(style: .white)
    }()
    private let noteLabel = UILabel()
    private let errorLabel = UILabel()
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var observer: UUID?
    private var layout: ContainerViewLayout?
    private var busy = false
    private var animatedIn = false
    private var leaving = false
    private var installedId: String?
    private var previousVersion: String?

    init(context: AccountContext, package: DGVerifiedPluginPackage) {
        self.context = context
        self.package = package
        self.manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
        self.blocksBackgroundWhenInOverlay = true
        self.navigationPresentation = .flatModal
        dgBindPluginAccount(context: context)
        self.observer = self.manager.observe { [weak self] in self?.update() }
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            self?.presentationData = data
            self?.update()
        })
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.presentationDisposable?.dispose()
        if let observer = self.observer { self.manager.removeObserver(observer) }
    }

    private func tr(_ ru: String, _ en: String) -> String {
        return self.presentationData.strings.primaryComponent.languageCode.hasPrefix("ru") ? ru : en
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .clear
        self.displayNode.view.addSubview(self.backdrop)
        self.displayNode.view.addSubview(self.sheet)
        self.backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        self.backdrop.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        self.sheet.layer.cornerRadius = 28
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.sheet.clipsToBounds = true
        self.sheet.addSubview(self.scroll)
        self.scroll.alwaysBounceVertical = false
        self.scroll.showsVerticalScrollIndicator = false
        self.scroll.contentInsetAdjustmentBehavior = .never
        for view in [self.grabber, self.typeLabel, self.closeButton, self.imageView, self.nameLabel, self.authorLabel, self.descriptionBackground, self.descriptionLabel, self.enabledLabel, self.enabledSwitch, self.installButton, self.noteLabel, self.errorLabel] { self.scroll.addSubview(view) }
        self.grabber.layer.cornerRadius = 2
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerRadius = 18
        self.imageView.image = dgPluginIcon(data: self.package.iconData, id: self.package.manifest.id, name: self.package.manifest.name, size: 68)
        for label in [self.nameLabel, self.authorLabel, self.descriptionLabel, self.enabledLabel, self.noteLabel, self.errorLabel] { label.numberOfLines = 0 }
        for label in [self.nameLabel, self.authorLabel, self.noteLabel] { label.textAlignment = .center }
        self.nameLabel.accessibilityTraits = .header
        self.descriptionBackground.layer.cornerRadius = 17
        self.closeButton.layer.cornerRadius = 17
        if #available(iOS 13.0, *) { self.closeButton.setImage(UIImage(systemName: "xmark"), for: .normal) }
        self.closeButton.accessibilityLabel = self.presentationData.strings.Common_Close
        self.closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        self.enabledSwitch.isOn = true
        self.installButton.layer.cornerRadius = 14
        self.installButton.addTarget(self, action: #selector(installPressed), for: .touchUpInside)
        self.installButton.addSubview(self.progress)
        self.errorLabel.accessibilityTraits = .staticText
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(closePressed))
        swipe.direction = .down
        self.typeLabel.isUserInteractionEnabled = true
        self.typeLabel.addGestureRecognizer(swipe)
        self.update()
    }

    private func update() {
        guard self.isNodeLoaded else { return }
        let theme = self.presentationData.theme
        let scale = min(2, max(0.8, self.presentationData.listsFontSize.itemListBaseFontSize / 17))
        let existing = self.manager.installations.first { $0.manifest.id == self.package.manifest.id }
        if !self.busy {
            self.previousVersion = existing?.manifest.version
            if let existing {
                let newerInstalled: Bool
                if let current = DGPluginSemanticVersion(existing.manifest.version), let offered = DGPluginSemanticVersion(self.package.manifest.version) { newerInstalled = current >= offered } else { newerInstalled = false }
                self.installedId = existing.digest == self.package.digest || newerInstalled ? existing.id : nil
            } else { self.installedId = nil }
        }
        let update = existing != nil && self.installedId == nil
        self.sheet.backgroundColor = theme.list.blocksBackgroundColor
        self.descriptionBackground.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.grabber.backgroundColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.4)
        self.typeLabel.textColor = theme.list.itemSecondaryTextColor
        self.typeLabel.text = update ? self.tr("Обновление плагина", "Plugin update") : self.tr("Плагин", "Plugin")
        self.typeLabel.font = .systemFont(ofSize: 13 * scale)
        self.closeButton.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.closeButton.tintColor = theme.list.itemSecondaryTextColor
        self.closeButton.isEnabled = !self.busy
        self.backdrop.isEnabled = !self.busy
        self.nameLabel.text = self.package.manifest.name
        self.nameLabel.font = .systemFont(ofSize: 24 * scale, weight: .semibold)
        self.nameLabel.textColor = theme.list.itemPrimaryTextColor
        let version = update ? (self.previousVersion ?? "") + " → " + self.package.manifest.version : (existing?.manifest.version ?? self.package.manifest.version)
        self.authorLabel.text = (self.package.manifest.author?.name ?? self.tr("Автор не указан", "Author not specified")) + " · " + version
        self.authorLabel.font = .systemFont(ofSize: 13 * scale)
        self.authorLabel.textColor = theme.list.itemSecondaryTextColor
        let changelog = self.package.manifest.changelog ?? ""
        self.descriptionLabel.text = update && !changelog.isEmpty ? changelog : self.package.manifest.description
        self.descriptionLabel.font = .systemFont(ofSize: 16 * scale)
        self.descriptionLabel.textColor = theme.list.itemPrimaryTextColor
        self.enabledLabel.text = update ? self.tr("Включить после обновления", "Enable after updating") : self.tr("Включить после установки", "Enable after installation")
        self.enabledLabel.font = .systemFont(ofSize: 15 * scale)
        self.enabledLabel.textColor = theme.list.itemPrimaryTextColor
        self.enabledSwitch.onTintColor = theme.list.itemAccentColor
        self.enabledSwitch.isEnabled = !self.busy
        self.enabledSwitch.accessibilityLabel = self.enabledLabel.text
        self.enabledSwitch.isHidden = self.installedId != nil
        self.enabledLabel.isHidden = self.enabledSwitch.isHidden
        self.installButton.backgroundColor = theme.list.itemAccentColor
        self.installButton.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.progress.color = theme.list.itemCheckColors.foregroundColor
        self.installButton.titleLabel?.font = .systemFont(ofSize: 17 * scale, weight: .semibold)
        self.installButton.titleLabel?.numberOfLines = 2
        self.installButton.titleLabel?.textAlignment = .center
        self.installButton.isEnabled = !self.busy
        self.installButton.alpha = self.busy ? 0.7 : 1
        self.installButton.setTitle(self.busy ? self.tr("Подождите…", "Please wait…") : self.installedId != nil ? self.tr("Открыть настройки", "Open settings") : update ? self.tr("Обновить", "Update") : self.tr("Установить", "Install"), for: .normal)
        self.noteLabel.text = self.installedId != nil ? self.tr("Плагин уже установлен", "Plugin already installed") : self.tr("Появится в настройках → Плагины", "Available in Settings → Plugins")
        self.noteLabel.font = .systemFont(ofSize: 12 * scale)
        self.noteLabel.textColor = theme.list.itemSecondaryTextColor
        self.errorLabel.font = .systemFont(ofSize: 14 * scale)
        self.errorLabel.textColor = theme.list.itemDestructiveColor
        if self.busy { self.progress.startAnimating() } else { self.progress.stopAnimating() }
        if let layout = self.layout { self.applyLayout(layout) }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.layout = layout
        if self.isNodeLoaded { self.applyLayout(layout) }
    }

    private func applyLayout(_ layout: ContainerViewLayout) {
        self.backdrop.frame = CGRect(origin: .zero, size: layout.size)
        let safe = layout.insets(options: [.statusBar])
        let left = layout.safeInsets.left
        let right = layout.safeInsets.right
        let width = min(480, max(1, layout.size.width - left - right))
        let inner = max(1, width - 40)
        self.grabber.frame = CGRect(x: (width - 32) / 2, y: 9, width: 32, height: 4)
        self.typeLabel.frame = CGRect(x: 21, y: 24, width: max(1, inner - 44), height: 40)
        self.closeButton.frame = CGRect(x: width - 61, y: 23, width: 44, height: 44)
        self.imageView.frame = CGRect(x: (width - 68) / 2, y: 74, width: 68, height: 68)
        func label(_ label: UILabel, x: CGFloat = 20, y: CGFloat, width: CGFloat) -> CGFloat {
            let height = ceil(label.sizeThatFits(CGSize(width: width, height: 100000)).height)
            label.frame = CGRect(x: x, y: y, width: width, height: height)
            return label.frame.maxY
        }
        var y = label(self.nameLabel, y: 157, width: inner)
        y = label(self.authorLabel, y: y + 6, width: inner)
        let descriptionY = y + 22
        y = label(self.descriptionLabel, x: 36, y: descriptionY + 16, width: max(1, inner - 32)) + 16
        self.descriptionBackground.frame = CGRect(x: 20, y: descriptionY, width: inner, height: y - descriptionY)
        y += 18
        if self.installedId == nil {
            let labelHeight = ceil(self.enabledLabel.sizeThatFits(CGSize(width: max(1, inner - 67), height: 100000)).height)
            let rowHeight = max(44, labelHeight)
            self.enabledLabel.frame = CGRect(x: 22, y: y + (rowHeight - labelHeight) / 2, width: max(1, inner - 67), height: labelHeight)
            self.enabledSwitch.frame = CGRect(x: width - 71, y: y + (rowHeight - 31) / 2, width: 51, height: 31)
            y += rowHeight + 15
        }
        if !(self.errorLabel.text ?? "").isEmpty { y = label(self.errorLabel, y: y, width: inner) + 14 }
        let buttonHeight = max(50, ceil((self.installButton.titleLabel?.font.lineHeight ?? 20) * 2) + 12)
        self.installButton.frame = CGRect(x: 20, y: y, width: inner, height: buttonHeight)
        self.progress.frame = CGRect(x: 15, y: (buttonHeight - 20) / 2, width: 20, height: 20)
        y = label(self.noteLabel, y: self.installButton.frame.maxY + 11, width: inner) + 20 + max(safe.bottom, layout.safeInsets.bottom)
        let height = min(y, max(1, layout.size.height - max(safe.top, layout.safeInsets.top) - 12))
        self.sheet.frame = CGRect(x: left + (layout.size.width - left - right - width) / 2, y: layout.size.height - height, width: width, height: height)
        self.scroll.frame = CGRect(x: 0, y: 0, width: width, height: height)
        self.scroll.contentSize = CGSize(width: width, height: y)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !self.animatedIn else { return }
        self.animatedIn = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        self.backdrop.alpha = 0
        self.sheet.transform = CGAffineTransform(translationX: 0, y: self.sheet.bounds.height)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            self.backdrop.alpha = 1
            self.sheet.transform = .identity
        })
    }

    override func dismiss(completion: (() -> Void)? = nil) {
        guard !self.leaving else { return }
        self.leaving = true
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2, animations: {
            self.backdrop.alpha = 0
            self.sheet.transform = CGAffineTransform(translationX: 0, y: self.sheet.bounds.height)
        }, completion: { [weak self] _ in self?.presentingViewController?.dismiss(animated: false, completion: completion) })
    }

    @objc private func closePressed() {
        if !self.busy { self.dismiss() }
    }

    @objc private func installPressed() {
        guard !self.busy, !self.leaving else { return }
        if let id = self.installedId {
            let context = self.context
            self.dismiss { context.sharedContext.presentGlobalController(dgInstalledPluginSettingsController(context: context, id: id), nil) }
            return
        }
        self.busy = true
        self.errorLabel.text = nil
        let enable = self.enabledSwitch.isOn
        let wasUpdate = self.previousVersion != nil
        self.update()
        self.manager.install(self.package) { [weak self] result in
            guard let self, !self.leaving else { return }
            switch result {
            case let .failure(error): self.failed(error)
            case let .success(id):
                if enable {
                    self.manager.setEnabled(id: id, enabled: true, reviewedDigest: self.package.digest) { [weak self] result in
                        guard let self, !self.leaving else { return }
                        switch result {
                        case .success: self.finished(id: id, update: wasUpdate)
                        case let .failure(error): self.failed(error)
                        }
                    }
                } else { self.finished(id: id, update: wasUpdate) }
            }
        }
    }

    private func failed(_ error: DGPluginError) {
        self.busy = false
        self.errorLabel.text = dgPluginErrorDescription(error, russian: self.presentationData.strings.primaryComponent.languageCode.hasPrefix("ru"))
        self.update()
        UIAccessibility.post(notification: .announcement, argument: self.errorLabel.text)
    }

    private func finished(id: String, update: Bool) {
        self.busy = false
        let context = self.context
        let text = self.package.manifest.name + " " + (update ? self.tr("обновлён", "updated") : self.tr("установлен", "installed"))
        let data = self.presentationData
        let action = self.tr("Настроить", "Settings")
        self.dismiss {
            context.sharedContext.presentGlobalController(UndoOverlayController(presentationData: data, content: .info(title: nil, text: text, timeout: nil, customUndoText: action), elevatedLayout: false, action: { event in
                if case .undo = event { context.sharedContext.presentGlobalController(dgInstalledPluginSettingsController(context: context, id: id), nil); return true }
                return false
            }), nil)
        }
    }
}
