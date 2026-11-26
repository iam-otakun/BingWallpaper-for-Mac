import Cocoa
import OSLog
import ServiceManagement

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Settings.rawValue
)

protocol SettingsVcDelegate: AnyObject {
    @MainActor
    func showMenuBarIcon()
    @MainActor
    func hideMenuBarIcon()
}

class SettingsVc: NSViewController {
    @IBOutlet var launchAtLoginCheckBox: NSButton!
    @IBOutlet weak var hideMenuBarIconCheckBox: NSButton!
    @IBOutlet var imagePathButton: NSButton!
    @IBOutlet weak var keepImagesSlider: NSSlider!
    @IBOutlet weak var keepImagesTextField: NSTextField!
    @IBOutlet weak var fileNameFormatEnglishButton: NSButton!
    @IBOutlet weak var fileNameFormatBilingualButton: NSButton!
    @IBOutlet weak var fileNameFormatLocalButton: NSButton!
    
    private let settings = Settings()
    weak var delegate: SettingsVcDelegate?
    weak var updateManager: UpdateManager?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refreshLaunchAtLoginCheckbox()
        hideMenuBarIconCheckBox.state = settings.hideMenuBarIcon ? .on : .off
        imagePathButton.title = settings.imageDownloadPath.path
        imagePathButton.toolTip = imagePathButton.title
        keepImagesSlider.integerValue = settings.keepImageDuration
        setKeepImagesText()
        refreshFileNameFormatButtons()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLaunchAtLoginCheckbox()
    }

    // MARK: - Actions

    @IBAction func launchAtLoginAction(_ sender: NSButton) {
        let newState = sender.state == .on
        do {
            try settings.setLaunchAtLogin(newState)
        } catch {
            logger.error("Failed to toggle launch-at-login: \(String(describing: error), privacy: .public)")
            refreshLaunchAtLoginCheckbox()
            presentLaunchAtLoginError(error)
            return
        }

        // Sync the checkbox to the real status 
        refreshLaunchAtLoginCheckbox()

        if newState, settings.launchAtLoginRequiresApproval {
            promptToApproveLoginItem()
        }
    }
    
    @IBAction func hideMenuBarIconCheckBoxAction(_ sender: NSButton) {
        let newState = sender.state == .on
        settings.hideMenuBarIcon = newState
        if newState == true {
            delegate?.hideMenuBarIcon()
        } else {
            delegate?.showMenuBarIcon()
        }
    }
    
    @IBAction func imagePathButtonAction(_ sender: NSButton) {
        let dialog = NSOpenPanel()
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = false
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = true
        
        if dialog.runModal() == NSApplication.ModalResponse.OK {
            guard let result = dialog.url else { return }
            settings.imageDownloadPath = result
            imagePathButton.title = result.path
            imagePathButton.toolTip = result.path
        }
    }
    
    @IBAction func keepImagesSliderAction(_ sender: NSSlider) {
        settings.keepImageDuration = sender.integerValue
        setKeepImagesText()
    }

    @IBAction func fileNameFormatAction(_ sender: NSButton) {
        guard let format = FileNameFormat(rawValue: sender.tag) else { return }
        settings.fileNameFormat = format
        refreshFileNameFormatButtons()
    }
    
    @IBAction func resetDatabaseButtonAction(_ sender: NSButton) {
        logger.info("Resetting Database...")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYYMMdd"
        let oldestDateStringToKeep = dateFormatter.string(from: Date())
        
        do {
           try Database.instance.deleteImageDescriptors(olderThan: oldestDateStringToKeep)
        } catch let error {
            logger.error("Failed resetting Database: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Failed to reset Database", comment: "Alert title")
            alert.informativeText = error.localizedDescription
            let updateButton = alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
            alert.alertStyle = .informational
            alert.window.defaultButtonCell = updateButton.cell as? NSButtonCell
            alert.runModal()
        }
        
        updateManager?.update()
    }
    
    // MARK: - Private

    private func refreshLaunchAtLoginCheckbox() {
        launchAtLoginCheckBox.state = settings.launchAtLogin ? .on : .off
    }

    private func refreshFileNameFormatButtons() {
        let format = settings.fileNameFormat
        fileNameFormatEnglishButton?.state = format == .english ? .on : .off
        fileNameFormatBilingualButton?.state = format == .bilingual ? .on : .off
        fileNameFormatLocalButton?.state = format == .local ? .on : .off
    }

    private func promptToApproveLoginItem() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Approve BingWallpaper in Login Items", comment: "Alert title")
        alert.informativeText = NSLocalizedString("BingWallpaper has been added to your Login Items but macOS needs your approval before it can launch at login. Open System Settings to confirm it.", comment: "Alert text")
        alert.alertStyle = .informational
        let openButton = alert.addButton(withTitle: NSLocalizedString("Open Login Items", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: "Button"))
        alert.window.defaultButtonCell = openButton.cell as? NSButtonCell

        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Couldn't update Launch at Login", comment: "Alert title")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
        alert.runModal()
    }

    private func setKeepImagesText() {
        guard let keepImageDuration = KeepImageDuration(rawValue: settings.keepImageDuration) else { return }
        
        switch keepImageDuration {
        case .five, .ten, .fifty, .onehundred:
            keepImagesTextField.stringValue = String(format: NSLocalizedString("Keep last %@ images:", comment: "Settings label; %@ is a number"), keepImageDuration.text)
        case .infinite:
            keepImagesTextField.stringValue = NSLocalizedString("Keep all images forever:", comment: "Settings label")
        }
    }
}

enum KeepImageDuration: Int {
    case five
    case ten
    case fifty
    case onehundred
    case infinite
    
    var text: String {
        switch self {
        case .five:
            return "5"
        case .ten:
            return "10"
        case .fifty:
            return "50"
        case .onehundred:
            return "100"
        case .infinite:
            return "∞"
        }
    }
}
