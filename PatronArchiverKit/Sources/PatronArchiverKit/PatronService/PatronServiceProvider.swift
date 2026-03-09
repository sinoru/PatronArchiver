import Foundation
import WebKit

public struct AccountInfo: Sendable {
    public let displayName: String
}

public protocol PatronServiceProvider: Sendable {
    static var matchPatterns: [any RegexComponent] { get }
    static var loginURL: URL { get }
    static var accountCheckURL: URL { get }
    static var siteIdentifier: String { get }

    init()

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool
    func preloadContent(in webView: WKWebView) async throws
    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem]
    func resolveTimeZone(in webView: WKWebView) async throws -> TimeZone?
    func extractMetadata(in webView: WKWebView, timeZone: TimeZone?) async throws -> PostMetadata

    static func parseAccountInfo(from data: Data) -> AccountInfo?
}

extension PatronServiceProvider {
    func resolveTimeZone(in webView: WKWebView) async throws -> TimeZone? { nil }

    func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func callAsyncJavaScript(
        _ script: String,
        arguments: [String: Any] = [:],
        in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            contentWorld: .page
        )
    }

    func parseMediaJSON(_ jsonString: String, referrerURL: URL?) -> [MediaItem] {
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return array.compactMap { dict -> MediaItem? in
            guard let urlString = dict["url"] as? String,
                  let url = URL(string: urlString)
            else { return nil }

            let typeString = dict["type"] as? String ?? "other"
            let type: MediaType = switch typeString {
            case "image": .image
            case "video": .video
            case "audio": .audio
            case "archive": .archive
            case "game": .game
            default: .other
            }

            let filename = dict["filename"] as? String
            return MediaItem(url: url, type: type, filename: filename, referrerURL: referrerURL)
        }
    }

    func parseMetadataJSON(
        _ jsonString: String,
        siteIdentifier: String,
        originalURL: URL,
        redirectChain: [URL],
        timeZone: TimeZone? = nil
    ) -> PostMetadata? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let postID = dict["postID"] as? String ?? ""
        let title = dict["title"] as? String ?? ""
        let authorName = dict["authorName"] as? String ?? ""
        let tags = dict["tags"] as? [String] ?? []

        let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        let isoFormatterNoFraction = ISO8601DateFormatter()

        let createdAt: Date
        if let timestamp = dict["createdAt"] as? Double {
            createdAt = Date(timeIntervalSince1970: timestamp / 1000)
        } else if let dateString = dict["createdAt"] as? String {
            createdAt = isoFormatter.date(from: dateString)
                ?? isoFormatterNoFraction.date(from: dateString)
                ?? Self.parseLocalizedDate(dateString, timeZone: timeZone)
                ?? Date()
        } else {
            createdAt = Date()
        }

        let modifiedAt: Date?
        if let timestamp = dict["modifiedAt"] as? Double {
            modifiedAt = Date(timeIntervalSince1970: timestamp / 1000)
        } else if let dateString = dict["modifiedAt"] as? String {
            modifiedAt = isoFormatter.date(from: dateString)
                ?? isoFormatterNoFraction.date(from: dateString)
                ?? Self.parseLocalizedDate(dateString, timeZone: timeZone)
        } else {
            modifiedAt = nil
        }

        return PostMetadata(
            siteIdentifier: siteIdentifier,
            postID: postID,
            title: title,
            authorName: authorName,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            tags: tags,
            originalURL: originalURL,
            redirectChain: redirectChain
        )
    }

    /// Parses a localized date string like `"Mar 03, 2026 08:10 am"` in the given time zone.
    private static func parseLocalizedDate(
        _ string: String,
        timeZone: TimeZone?
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd, yyyy hh:mm a"
        formatter.timeZone = timeZone ?? .gmt
        return formatter.date(from: string)
    }
}
