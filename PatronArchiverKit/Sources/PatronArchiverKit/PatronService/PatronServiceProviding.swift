import Foundation
import WebKit

public protocol PatronServiceProviding: Sendable {
    static var matchPatterns: [Regex<Substring>] { get }
    static var loginURL: URL { get }
    static var accountCheckURL: URL { get }
    static var siteIdentifier: String { get }

    init()

    static func isLoggedIn(cookies: [HTTPCookie]) -> Bool
    @MainActor func preloadContent(in webView: WKWebView) async throws
    @MainActor func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem]
    @MainActor func resolveTimeZone(in webView: WKWebView) async throws -> TimeZone?
    @MainActor func extractMetadata(in webView: WKWebView, timeZone: TimeZone?) async throws -> PostMetadata

    static func parseAccountInfo(from data: Data) -> AccountInfo?
}

extension PatronServiceProviding {
    @MainActor func resolveTimeZone(in webView: WKWebView) async throws -> TimeZone? { nil }

    @MainActor func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    @MainActor func callAsyncJavaScript(
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
