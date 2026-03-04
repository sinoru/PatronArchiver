import Foundation
import WebKit

struct AccountInfo: Sendable {
    let displayName: String
}

protocol PatronServiceProvider: Sendable {
    static var matchPatterns: [String] { get }
    static var loginURL: URL { get }
    static var accountCheckURL: URL { get }
    static var siteIdentifier: String { get }

    init()

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool
    func preloadContent(in webView: WKWebView) async throws
    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem]
    func extractMetadata(in webView: WKWebView) async throws -> PostMetadata

    static func parseAccountInfo(from data: Data) -> AccountInfo?
}

extension PatronServiceProvider {
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
        redirectChain: [URL]
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
}
