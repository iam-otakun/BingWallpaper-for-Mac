//
//  Image.swift
//  BingWallpaper
//
//  Created by Laurenz Lazarus on 23.03.24.
//

import Foundation

class Image {
    enum Error: Swift.Error {
        case missingDescriptor
    }
    
    private weak var descriptor: ImageDescriptor?

    init(descriptor: ImageDescriptor) {
        self.descriptor = descriptor
    }

    /// Where this image lives (or will live) on disk. The file name is the
    /// one resolved at download time for the user's naming format; before
    /// resolution it falls back to the legacy `<startDate>.jpg`.
    var downloadPath: URL {
        guard let descriptor else {
            return FileHandler.defaultBingWallpaperDirectory()
        }
        return FileHandler.defaultBingWallpaperDirectory().appendingPathComponent(Image.fileName(for: descriptor))
    }

    static func fileName(for descriptor: ImageDescriptor) -> String {
        return Settings().storedFileName(forStartDate: descriptor.startDate) ?? (descriptor.startDate + ".jpg")
    }

    func loadFromDisk() async throws -> Data {
        return try Data(contentsOf: downloadPath)
    }

    func downloadAndSaveToDisk() async throws {
        guard let descriptor else {
            throw Error.missingDescriptor
        }
        // Resolve and remember the display file name first; Bing only
        // serves recent days, so it cannot be recomputed later.
        let settings = Settings()
        if settings.storedFileName(forStartDate: descriptor.startDate) == nil {
            let resolved = await FileNameResolver.resolveFileName(for: descriptor, format: settings.fileNameFormat)
            settings.storeFileName(resolved, forStartDate: descriptor.startDate)
        }
        let imageData = try await DownloadManager.downloadBinary(from: descriptor.imageUrl)
        try FileHandler.saveImageDataToDisk(imageData: imageData, toUrl: downloadPath)
    }

    static func isSavedToDisk(descriptor: ImageDescriptor) -> Bool {
        let imagePath = FileHandler.defaultBingWallpaperDirectory() + "/" + fileName(for: descriptor)
        return FileManager.default.fileExists(atPath: imagePath)
    }
    
    func isOnDisk() -> Bool {
        return FileManager.default.fileExists(atPath: downloadPath.relativePath)
    }
}
