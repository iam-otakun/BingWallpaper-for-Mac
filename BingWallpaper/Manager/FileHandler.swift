import AppKit
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.FileHandler.rawValue
)

class FileHandler {
    static func usersPictureDirectory() -> String {
        guard let picturesDirectory = NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first else {
            logger.error("Couldn't find picture directory of user")
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        
        return picturesDirectory
    }
    
    static func defaultBingWallpaperDirectory() -> String {
        return usersPictureDirectory() + "/bing-wallpapers/"
    }
    
    static func defaultBingWallpaperDirectory() -> URL {
        return URL(fileURLWithPath: defaultBingWallpaperDirectory(), isDirectory: true)
    }
    
    static func createWallpaperFolderIfNeeded() {
        let bingDir: String = Settings().imageDownloadPath.path
        
        if FileManager.default.fileExists(atPath: bingDir) { return }
        
        do {
            try FileManager.default.createDirectory(atPath: bingDir, withIntermediateDirectories: false)
        } catch {
            logger.error("Failed to create bing-wallpapers folder with error: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    static func saveImageToDisk(image: NSImage, toUrl: URL) {
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation),
              let imageData = bitmap.representation(using: .jpeg, properties: [:]) else { return }
        
        do {
            try imageData.write(to: toUrl, options: .withoutOverwriting)
        } catch {
            logger.error("Failed to save image to disk with error: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    static func saveImageDataToDisk(imageData: Data, toUrl: URL) throws {
        try imageData.write(to: toUrl, options: .withoutOverwriting)
    }
    
    static func getSavedImages() -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: Settings().imageDownloadPath, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles)
        } catch {
            logger.error("Failed to list saved images: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    static func removeImageFromDisk(imagePath: URL) {
        do {
            return try FileManager.default.removeItem(at: imagePath)
        } catch {
            logger.error("Failed to remove image at \(imagePath.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
    }
    
    static func deleteOldImages(oldestDateStringToKeep: String) {
        getSavedImages()
            .filter { dateString(of: $0) <= oldestDateStringToKeep }
            .forEach { removeImageFromDisk(imagePath: $0) }
    }

    /// The `yyyyMMdd` date encoded in an image file name, for both the
    /// legacy `20261120.jpg` form and the named
    /// `Bing_2026-11-20_....jpg` form.
    private static func dateString(of url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix("Bing_") {
            let datePart = name.dropFirst("Bing_".count).prefix(10)
            let digits = datePart.replacingOccurrences(of: "-", with: "")
            if digits.count == 8, digits.allSatisfy({ $0.isNumber }) {
                return digits
            }
        }
        return name.replacingOccurrences(of: ".jpg", with: "")
    }
    
    static func savePkgInstallerToDisk(pkgInstaller: Data, appVersion: String) -> URL? {
        let temporaryDirectoryUrl = pkgInstallerPathUrl(appVersion: appVersion)
        do {
            try pkgInstaller.write(to: temporaryDirectoryUrl)
        } catch {
            logger.error("Failed to save pkg installer to disk with error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        
        return temporaryDirectoryUrl
    }
    
    static func pkgInstallerAlreadyDownloaded(appVersion: String) -> URL? {
        let temporaryDirectoryUrl = pkgInstallerPathUrl(appVersion: appVersion)
        if FileManager.default.fileExists(atPath: temporaryDirectoryUrl.relativePath) == true {
            return temporaryDirectoryUrl
        }
        
        return nil
    }
    
    static func pkgInstallerPathUrl(appVersion: String) -> URL {
        var temporaryDirectoryUrl = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        temporaryDirectoryUrl.appendPathComponent("BingWallpaper_" + appVersion + ".pkg")
        return temporaryDirectoryUrl
    }
}
