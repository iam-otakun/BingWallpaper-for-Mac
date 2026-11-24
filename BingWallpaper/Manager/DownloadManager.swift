import Cocoa
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Download.rawValue
)

class DownloadManager {
    
    struct ImageArchive: Codable {
        let images: [ImageEntry]
    }
    
    struct ImageEntry: Codable {
        let url: String
        let enddate: String
        let startdate: String
        let copyright: String
        let copyrightlink: String
        let title: String?
    }
    
    private static func downloadData(from url: URL) async throws-> DownloadResponse {
        let (data, urlResponse) = try await URLSession.shared.data(from: url)
        return DownloadResponse(data: data, urlResponse: urlResponse)
    }
    
    private static func downloadHttpHead(from url: URL) async throws -> DownloadResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "HEAD"
        let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        return DownloadResponse(data: data, urlResponse: urlResponse)
    }
    
    static func downloadImageEntries(numberOfImages: Int) async throws -> [ImageEntry] {
        // TODO: @2h4u: idx is the start index of the batch of image descriptors that is downloaded, maybe add support for it so more images from the past can be used?
        let response = try await downloadData(from: URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&n=\(numberOfImages)&idx=0")!)
        return try JSONDecoder().decode(ImageArchive.self, from: response.data).images
    }

    /// Fetch entries with the Bing market pinned via `mkt`, so the result
    /// does not depend on the request's exit IP (the no-`mkt` variant above
    /// lets Bing guess the market).
    static func downloadImageEntries(numberOfImages: Int, market: String) async throws -> [ImageEntry] {
        let response = try await downloadData(from: URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&n=\(numberOfImages)&idx=0&mkt=\(market)")!)
        return try JSONDecoder().decode(ImageArchive.self, from: response.data).images
    }
    
    static func downloadHtml(from url: URL) async -> String? {
        do {
            let response = try await downloadData(from: url)
            return String(data: response.data, encoding: .utf8)
        } catch let error {
            logger.error("Failed to download HTML from \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    static func downloadHtmlHeaders(from url: URL) async -> URLResponse? {
        do {
            return try await downloadHttpHead(from: url).urlResponse
        } catch let error {
            logger.error("Failed to download HTML headers from \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    static func downloadBinary(from url: URL) async throws -> Data {
        return try await downloadData(from: url).data
    }
}

/// Builds the on-disk file name for a wallpaper image following the
/// user-selected `FileNameFormat`.
///
/// The keyword derivation mirrors Fred's Synology `bing-wallpaper.sh`:
/// keywords are the first segment of the market's `copyright` text (up to
/// the opening parenthesis of the credit), with commas and spaces turned
/// into underscores. Images are matched across markets by their `OHR.`
/// identity, which is stable across markets even though the markets roll
/// over to a new image at different times of day.
enum FileNameResolver {

    /// Resolve the file name for a descriptor. Falls back to the legacy
    /// `<startDate>.jpg` whenever the market metadata cannot be fetched
    /// or the image cannot be matched, so a download never fails because
    /// of naming.
    static func resolveFileName(for descriptor: ImageDescriptor, format: FileNameFormat) async -> String {
        let fallback = descriptor.startDate + ".jpg"
        guard let key = imageKey(from: descriptor.imageUrl.absoluteString) else { return fallback }

        do {
            switch format {
            case .english:
                let entries = try await DownloadManager.downloadImageEntries(numberOfImages: 8, market: "en-US")
                guard let entry = match(entries, forKey: key) else { return fallback }
                return buildName(date: entry.startdate, keywordSegments: [keywords(from: entry.copyright)])
            case .bilingual:
                async let enEntries = DownloadManager.downloadImageEntries(numberOfImages: 8, market: "en-US")
                async let zhEntries = DownloadManager.downloadImageEntries(numberOfImages: 9, market: "zh-CN")
                let (en, zh) = try await (enEntries, zhEntries)
                guard let enEntry = match(en, forKey: key) else { return fallback }
                let kwEn = keywords(from: enEntry.copyright)
                if let zhEntry = match(zh, forKey: key) {
                    // Same rule as bing-wallpaper.sh: the date and the
                    // Chinese keywords come from the Chinese-market entry
                    // for this very image, the English keywords follow
                    // after a hyphen.
                    let kwZh = keywords(from: zhEntry.copyright)
                    var name = "Bing_\(dashedDate(zhEntry.startdate))"
                    if !kwZh.isEmpty { name += "_\(kwZh)" }
                    if !kwEn.isEmpty { name += kwZh.isEmpty ? "_\(kwEn)" : "-\(kwEn)" }
                    return name + ".jpg"
                }
                return buildName(date: enEntry.startdate, keywordSegments: [kwEn])
            case .local:
                let entries = try await DownloadManager.downloadImageEntries(numberOfImages: 8, market: localMarket())
                guard let entry = match(entries, forKey: key) else { return fallback }
                return buildName(date: entry.startdate, keywordSegments: [keywords(from: entry.copyright)])
            }
        } catch {
            logger.error("Failed to resolve file name for \(descriptor.startDate, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    /// The `OHR.<key>` identity of an image URL, stable across markets.
    static func imageKey(from urlString: String) -> String? {
        guard let range = urlString.range(of: "OHR.") else { return nil }
        let key = urlString[range.upperBound...].prefix { $0 != "_" }
        return key.isEmpty ? nil : String(key)
    }

    static func keywords(from copyright: String) -> String {
        let disallowed = CharacterSet(charactersIn: "()\\/:*?\"<>")
        let head = copyright.components(separatedBy: disallowed).first { !$0.isEmpty } ?? ""
        var result = head
            .replacingOccurrences(of: "，", with: "_")
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// The Bing market matching the user's system language/region.
    static func localMarket() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        let known: [String: String] = [
            "zh_CN": "zh-CN", "zh_TW": "zh-TW", "zh_HK": "zh-HK",
            "en_US": "en-US", "en_GB": "en-GB", "en_AU": "en-AU",
            "en_CA": "en-CA", "en_IN": "en-IN", "en_NZ": "en-NZ",
            "ja_JP": "ja-JP", "de_DE": "de-DE", "fr_FR": "fr-FR",
            "fr_CA": "fr-CA", "es_ES": "es-ES", "es_MX": "es-MX",
            "it_IT": "it-IT", "pt_BR": "pt-BR", "pt_PT": "pt-PT",
            "ko_KR": "ko-KR", "ru_RU": "ru-RU", "nl_NL": "nl-NL",
            "pl_PL": "pl-PL", "sv_SE": "sv-SE", "da_DK": "da-DK",
            "nb_NO": "nb-NO", "fi_FI": "fi-FI", "tr_TR": "tr-TR"
        ]
        if let market = known["\(language)_\(region)"] {
            return market
        }
        return language == "zh" ? "zh-CN" : "en-US"
    }

    private static func match(_ entries: [DownloadManager.ImageEntry], forKey key: String) -> DownloadManager.ImageEntry? {
        return entries.first { imageKey(from: $0.url) == key || imageKey(from: "https://www.bing.com" + $0.url) == key }
    }

    private static func buildName(date startdate: String, keywordSegments: [String]) -> String {
        var name = "Bing_\(dashedDate(startdate))"
        for segment in keywordSegments where !segment.isEmpty {
            name += "_\(segment)"
        }
        return name + ".jpg"
    }

    private static func dashedDate(_ startdate: String) -> String {
        guard startdate.count == 8 else { return startdate }
        let year = startdate.prefix(4)
        let month = startdate.dropFirst(4).prefix(2)
        let day = startdate.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }
}
