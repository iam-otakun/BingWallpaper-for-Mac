import Cocoa
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Menu.rawValue
)

class MenuController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var stickItem: NSMenuItem?
    private let settings = Settings()
    private var descriptors = [ImageDescriptor]()
    private var selectedDescriptorIndex = 0
    private var imageSelectorView: ImageSelectorView!
    var updateManager: UpdateManager?
    private static let IMAGE_VIEW_TAG = 6
    private static let TEXT_VIEW_TAG = 7
    private lazy var settingsWc = SettingsWc.instance()
    
    // MARK: - UI setup
    
    @MainActor
    func setup() {
        guard self.statusItem == nil && self.menu == nil else { return }
        if settings.hideMenuBarIcon == true { return }
        
        self.statusItem = createStatusBarItem()
        self.menu = createMenu()
        self.statusItem!.menu = menu
        
        showNewestImage()
    }
    
    private func createStatusBarItem() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "BingWallpaper")
        }
        
        return statusItem
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 300
        
        let imageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        imageSelectorView = ImageSelectorView(frame: CGRect(x: 0, y: 0, width: menu.size.width, height: imageSelectorViewHeight(menu: menu)))
        imageSelectorView.leftButton.action = #selector(MenuController.imageSelectorViewLeftButtonAction)
        imageSelectorView.leftButton.target = self
        imageSelectorView.rightButton.action = #selector(MenuController.imageSelectorViewRightButtonAction)
        imageSelectorView.rightButton.target = self
        imageItem.view = imageSelectorView
        imageItem.tag = MenuController.IMAGE_VIEW_TAG
        menu.addItem(imageItem)
        
        menu.addItem(NSMenuItem.separator())

        let stickItem = NSMenuItem(title: "Stick With This Picture", action: #selector(toggleStick), keyEquivalent: "")
        stickItem.target = self
        stickItem.state = settings.stickWithCurrentPicture ? .on : .off
        menu.addItem(stickItem)
        self.stickItem = stickItem

        menu.addItem(NSMenuItem.separator())

        let openFolderItem = NSMenuItem(title: "Open Photo Folder", action: #selector(openPhotoFolder), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let refreshItem = NSMenuItem(title: "Refresh Images", action: #selector(refreshImages), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        
        let appUpdateItem = NSMenuItem(title: "Check for app update", action: #selector(checkForAppUpdate), keyEquivalent: "")
        appUpdateItem.target = self
        menu.addItem(appUpdateItem)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettingsWc), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About…", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    // MARK: - IBActions
    
    @MainActor
    @objc func showSettingsWc(sender: NSMenuItem?) {
        (settingsWc.contentViewController as! SettingsVc).delegate = self
        (settingsWc.contentViewController as! SettingsVc).updateManager = updateManager
        settingsWc.showWindow(self)
        settingsWc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    @objc func refreshImages(sender: NSMenuItem) {
        updateManager?.update { outcome in
            let message: String
            switch outcome {
            case .updated:
                message = "Update successfully!"
            case .upToDate:
                message = "Up to date!"
            case .failed:
                message = "Update failed!"
            }
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            let okButton = alert.addButton(withTitle: "Ok")
            alert.window.defaultButtonCell = okButton.cell as? NSButtonCell
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    
    @MainActor
    @objc func toggleStick(sender: NSMenuItem) {
        let newValue = !settings.stickWithCurrentPicture
        settings.stickWithCurrentPicture = newValue
        sender.state = newValue ? .on : .off
        if newValue {
            // Pin whatever is on screen right now.
            if let descriptor = descriptors[safe: selectedDescriptorIndex] {
                settings.currentImageStartDate = descriptor.startDate
            }
        } else {
            // Stick released: today's picture goes up right away.
            showNewestImage()
        }
    }

    @MainActor
    @objc func openPhotoFolder(sender: NSMenuItem) {
        FileHandler.createWallpaperFolderIfNeeded()
        NSWorkspace.shared.open(settings.imageDownloadPath)
    }
    
    @MainActor
    // The house About, same as our Windows and macOS programs: the
    // standard about panel shows name and version from the bundle;
    // the credits carry Idea: Otakun, Coding: Dash and a link labelled
    // "GitHub Repository" (never the raw URL as the link text).
    @objc func showAbout(sender: NSMenuItem?) {
        let credits = NSMutableAttributedString()
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        credits.append(NSAttributedString(string: "Idea: Otakun\nCoding: Dash\n", attributes: textAttrs))
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://github.com/iam-otakun/BingWallpaper-for-Mac")!
        ]
        credits.append(NSAttributedString(string: "GitHub Repository", attributes: linkAttrs))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func checkForAppUpdate(sender: NSMenuItem) {
        Task {
            await AppUpdateManager.checkForUpdate()
        }
    }
    
    @MainActor
    @objc func imageSelectorViewLeftButtonAction(_ sender: NSButton) {
        if descriptors.indices.contains(selectedDescriptorIndex - 1) == false {
            return
        }
        
        selectedDescriptorIndex = selectedDescriptorIndex - 1
        updateSelectedImage(newSelectedDescriptorIndex: selectedDescriptorIndex)
        updateImageSelectorView(newSelectedDescriptorIndex: selectedDescriptorIndex)
    }
    
    @MainActor
    @objc func imageSelectorViewRightButtonAction(_ sender: NSButton) {
        if descriptors.indices.contains(selectedDescriptorIndex + 1) == false {
            return
        }
        
        selectedDescriptorIndex = selectedDescriptorIndex + 1
        updateSelectedImage(newSelectedDescriptorIndex: selectedDescriptorIndex)
        updateImageSelectorView(newSelectedDescriptorIndex: selectedDescriptorIndex)
    }
    
    @MainActor
    @objc func textItemAction(sender: NSMenuItem) {
        if let descriptor = descriptors[safe: selectedDescriptorIndex] {
            NSWorkspace.shared.open(descriptor.copyrightUrl)
        }
    }
    
    // MARK: - Helper
    
    private func imageSelectorViewHeight(menu: NSMenu) -> CGFloat {
        let outerPadding = 5.0
        let buttonWidth = 15.0
        let innerPadding = 5.0
        let imageViewWidth = menu.size.width - outerPadding*2 - buttonWidth*2 - innerPadding*2
        let topMargin = 4.0
        return imageViewWidth / 16*9 + topMargin
    }
    
    private func updateSelectedImage(newSelectedDescriptorIndex: Int) {
        if let descriptor = descriptors[safe: newSelectedDescriptorIndex] {
            WallpaperManager.shared.setWallpaper(descriptor: descriptor)
            settings.currentImageStartDate = descriptor.startDate
        }
    }
    
    @MainActor
    private func updateImageSelectorView(newSelectedDescriptorIndex: Int) {
        guard let menu = menu else { return }
        
        let descriptor = descriptors[safe: newSelectedDescriptorIndex]
        Task {
            guard let descriptor else { return }
            do {
                let imageData = try await descriptor.image.loadFromDisk()
                await MainActor.run { [weak self] in
                    self?.imageSelectorView.imageView.image = NSImage(data: imageData)
                }
            } catch {
                logger.error("Failed to load image from disk: \(String(describing: descriptor), privacy: .public)")
            }
        }
        
        let textItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        textItem.tag = MenuController.TEXT_VIEW_TAG
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: menu.size.width, height: 0))
        textView.descriptionLabel.stringValue = getDescription(description: descriptor?.descriptionString)
        textView.copyrightLabel.stringValue = getCopyright(description: descriptor?.descriptionString)
        textView.button.action = #selector(textItemAction)
        textView.button.target = self
        textItem.view = textView
        
        if let oldTextItem = menu.item(withTag: MenuController.TEXT_VIEW_TAG) {
            menu.removeItem(oldTextItem)
        }
        let imageView = menu.item(withTag: MenuController.IMAGE_VIEW_TAG)!
        let textViewIndex = menu.index(of: imageView) + 1
        menu.insertItem(textItem, at: textViewIndex)
        
        imageSelectorView.leftButton.isEnabled = descriptors.indices.contains(newSelectedDescriptorIndex - 1)
        imageSelectorView.rightButton.isEnabled = descriptors.indices.contains(newSelectedDescriptorIndex + 1)
    }
    
    private func getDescription(description: String?) -> String {
        if description == nil { return "" }
        return String(description?.split(separator: "(").first ?? "")
    }
    
    private func getCopyright(description: String?) -> String {
        if description == nil { return "" }
        return description?.split(separator: "(").last?.replacingOccurrences(of: ")", with: "") ?? ""
    }
    
    @MainActor
    private func showNewestImage() {
        self.descriptors = Database.instance.allImageDescriptors()
            .filter { $0.image.isOnDisk() }
        // Stick is on and the pinned picture is still around: restore it
        // instead of jumping to the newest (e.g. right after a relaunch).
        if settings.stickWithCurrentPicture,
           let pinnedStartDate = settings.currentImageStartDate,
           let pinnedIndex = self.descriptors.firstIndex(where: { $0.startDate == pinnedStartDate }) {
            selectedDescriptorIndex = pinnedIndex
            updateSelectedImage(newSelectedDescriptorIndex: selectedDescriptorIndex)
            return
        }
        selectedDescriptorIndex = self.descriptors.firstIndex(where: { $0 == self.descriptors.last }) ?? self.descriptors.endIndex
        updateSelectedImage(newSelectedDescriptorIndex: selectedDescriptorIndex)
    }

    /// Reload the descriptor list after a background download while stick
    /// is on: the archive grows, but the selection (and the wallpaper)
    /// stays on the pinned picture.
    @MainActor
    private func refreshDescriptorsKeepingSelection() {
        let currentStartDate = settings.currentImageStartDate
        self.descriptors = Database.instance.allImageDescriptors()
            .filter { $0.image.isOnDisk() }
        if let currentStartDate,
           let index = self.descriptors.firstIndex(where: { $0.startDate == currentStartDate }) {
            selectedDescriptorIndex = index
        } else if self.descriptors.isEmpty == false {
            selectedDescriptorIndex = min(selectedDescriptorIndex, self.descriptors.count - 1)
        }
        updateImageSelectorView(newSelectedDescriptorIndex: selectedDescriptorIndex)
    }
}

// MARK: - Delegates

extension MenuController: UpdateManagerDelegate {
    func downloadedNewImage() {
        if settings.stickWithCurrentPicture {
            refreshDescriptorsKeepingSelection()
        } else {
            showNewestImage()
        }
    }
}

extension MenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateImageSelectorView(newSelectedDescriptorIndex: selectedDescriptorIndex)
    }
}

extension MenuController: SettingsVcDelegate {
    func showMenuBarIcon() {
        setup()
    }
    
    func hideMenuBarIcon() {
        guard let statusItem = statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.menu?.removeAllItems()
        self.menu = nil
        self.statusItem = nil
    }
}
