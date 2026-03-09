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

    static func isLoggedIn(cookies: [HTTPCookie]) -> Bool
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

    static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

enum ProviderError: LocalizedError {
    case metadataExtractionFailed
    case mediaExtractionFailed

    var errorDescription: String? {
        switch self {
        case .metadataExtractionFailed: "Failed to extract metadata."
        case .mediaExtractionFailed: "Failed to extract media."
        }
    }
}
