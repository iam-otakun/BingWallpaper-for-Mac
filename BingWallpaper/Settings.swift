
import Foundation
import ServiceManagement
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Settings.rawValue
)

public class Settings {
    private let defaults = UserDefaults.standard

    public init() {
        migrateLegacyLoginItemIfNeeded()
    }

    /// `true` when the user's intent is "launch at login enabled".
    ///
    /// On macOS 15+/26 the system frequently keeps a freshly registered login
    /// item in `.requiresApproval` until the user confirms it in
    /// System Settings → General → Login Items. We treat that as "on" so the
    /// checkbox doesn't snap back to off the instant the user toggles it.
    var launchAtLogin: Bool {
        if LaunchAgentLoginItem.isEnabled {
            return true
        }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    /// `true` when the login item is registered but waiting for the user to
    /// approve it in System Settings. Callers should route the user there.
    var launchAtLoginRequiresApproval: Bool {
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Register or unregister the main app as a login item. Throws on failure
    /// so the caller can surface the error to the user instead of swallowing
    /// it.
    ///
    /// `SMAppService` registration can fail for self-built / ad-hoc signed
    /// copies of the app, so on failure we fall back to a per-user
    /// LaunchAgent, which provides the same launch-at-login behaviour.
    func setLaunchAtLogin(_ newValue: Bool) throws {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // The modern path worked; make sure no fallback agent lingers.
            try? LaunchAgentLoginItem.setEnabled(false)
        } catch {
            let actionString = newValue ? "register" : "unregister"
            logger.error("Failed to \(actionString, privacy: .public) login item with error: \(String(describing: error), privacy: .public). Falling back to LaunchAgent.")
            do {
                try LaunchAgentLoginItem.setEnabled(newValue)
            } catch {
                throw error
            }
        }
    }

    private func migrateLegacyLoginItemIfNeeded() {
        guard defaults.object(forKey: Settings.SM_LOGIN_ENABLED_LEGACY) != nil else { return }
        let wasEnabled = defaults.bool(forKey: Settings.SM_LOGIN_ENABLED_LEGACY)
        defaults.removeObject(forKey: Settings.SM_LOGIN_ENABLED_LEGACY)
        if wasEnabled, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }
    
    var hideMenuBarIcon: Bool {
        get {
            return defaults.bool(forKey: Settings.HIDE_MENU_BAR_ICON)
        }
        set {
            defaults.set(newValue, forKey: Settings.HIDE_MENU_BAR_ICON)
        }
    }
    
    var imageDownloadPath: URL {
        get {
            return defaults.url(forKey: Settings.IMAGE_DOWNLOAD_PATH) ?? FileHandler.defaultBingWallpaperDirectory()
        }
        set {
            defaults.set(newValue, forKey: Settings.IMAGE_DOWNLOAD_PATH)
        }
    }
    
    public var lastUpdate: Date {
        get {
            return defaults.object(forKey: Settings.LAST_UPDATE) as? Date ?? Date.distantPast
        }
        set {
            defaults.set(newValue, forKey: Settings.LAST_UPDATE)
        }
    }
    
    var keepImageDuration: Int {
        get {
            return defaults.object(forKey: Settings.KEEP_IMAGE_DURATION) as? Int ?? KeepImageDuration.fifty.rawValue
        }
        set {
            defaults.set(newValue, forKey: Settings.KEEP_IMAGE_DURATION)
        }
    }
    
    private func keepImageTimeInterval() -> TimeInterval? {
        let durationInDays: Double?
        
        switch keepImageDuration {
        case KeepImageDuration.five.rawValue:
            durationInDays = 5
        case KeepImageDuration.ten.rawValue:
            durationInDays = 10
        case KeepImageDuration.fifty.rawValue:
            durationInDays = 50
        case KeepImageDuration.onehundred.rawValue:
            durationInDays = 100
        case KeepImageDuration.infinite.rawValue:
            durationInDays = nil
        default:
            durationInDays = 50
        }
        
        guard let durationInDays = durationInDays else {
            return nil
        }
        
        return durationInDays * 3600.0 * 24.0
    }
    
    func oldestDateToKeep() -> Date? {
        guard let keepImageTimeInterval = keepImageTimeInterval() else {
            return nil
        }
        return Date().addingTimeInterval(-keepImageTimeInterval)
    }
    
    func oldestDateStringToKeep() -> String? {
        guard let oldestDateToKeep = oldestDateToKeep() else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        return dateFormatter.string(from: oldestDateToKeep)
    }
    
    /// How downloaded images are named on disk. Chosen by the user in
    /// Settings; defaults to `.english`.
    var fileNameFormat: FileNameFormat {
        get {
            return FileNameFormat(rawValue: defaults.integer(forKey: Settings.FILE_NAME_FORMAT)) ?? .english
        }
        set {
            defaults.set(newValue.rawValue, forKey: Settings.FILE_NAME_FORMAT)
        }
    }

    /// The resolved on-disk file name for the image of a given start date
    /// (`yyyyMMdd`), remembered when the image was downloaded. The name
    /// cannot be recomputed later because Bing only serves recent days.
    func storedFileName(forStartDate startDate: String) -> String? {
        return (defaults.dictionary(forKey: Settings.FILE_NAME_MAP) as? [String: String])?[startDate]
    }

    func storeFileName(_ fileName: String, forStartDate startDate: String) {
        var map = (defaults.dictionary(forKey: Settings.FILE_NAME_MAP) as? [String: String]) ?? [:]
        map[startDate] = fileName
        defaults.set(map, forKey: Settings.FILE_NAME_MAP)
    }

    func removeStoredFileNames(olderThan oldestDateString: String) {
        guard var map = (defaults.dictionary(forKey: Settings.FILE_NAME_MAP) as? [String: String]) else { return }
        map = map.filter { $0.key > oldestDateString }
        defaults.set(map, forKey: Settings.FILE_NAME_MAP)
    }

    private static let SM_LOGIN_ENABLED_LEGACY = "SM_LOGIN_ENABLED"
    private static let HIDE_MENU_BAR_ICON = "HIDE_MENU_BAR_ICON"
    private static let IMAGE_DOWNLOAD_PATH = "IMAGE_DOWNLOAD_PATH"
    private static let LAST_UPDATE = "LAST_UPDATE"
    private static let KEEP_IMAGE_DURATION = "KEEP_IMAGE_DURATION"
    private static let FILE_NAME_FORMAT = "FILE_NAME_FORMAT"
    private static let FILE_NAME_MAP = "FILE_NAME_MAP"
}

/// The user-selectable naming scheme for downloaded wallpaper files.
enum FileNameFormat: Int {
    /// `Bing_2026-11-20_English_Name.jpg`
    case english = 0
    /// `Bing_2026-11-20_中文关键词-English_Name.jpg` (same rule as the
    /// Synology `bing-wallpaper.sh` archive)
    case bilingual = 1
    /// Title taken from the Bing market matching the system language.
    case local = 2
}

/// Fallback launch-at-login via a per-user LaunchAgent, used when
/// `SMAppService` registration fails (notably for self-built, ad-hoc
/// signed copies of the app).
enum LaunchAgentLoginItem {
    private static var plistURL: URL {
        let label = Bundle.main.bundleIdentifier ?? "com.2h4u.BingWallpaper"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).launch.plist")
    }

    static var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let executablePath = Bundle.main.executablePath else {
                throw NSError(domain: "LaunchAgentLoginItem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate the app executable"])
            }
            let label = Bundle.main.bundleIdentifier ?? "com.2h4u.BingWallpaper"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
