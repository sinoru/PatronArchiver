import Foundation
import WebKit

public enum LoginChecker {
    /// Checks login status by examining cookies only — fast, no network request.
    public static func isLoggedIn(
        for providerType: any PatronServiceProvider.Type,
        dataStore: WKWebsiteDataStore
    ) async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return providerType.isLoggedIn(cookies: cookies)
    }

    /// Fetches account info by making an HTTP request to the provider's accountCheckURL.
    ///
    /// - Returns: The account info if successfully fetched, nil otherwise.
    @MainActor
    public static func fetchAccountInfo(
        for providerType: any PatronServiceProvider.Type,
        dataStore: WKWebsiteDataStore
    ) async -> AccountInfo? {
        let url = providerType.accountCheckURL
        var urlRequest = URLRequest(url: url)
        await dataStore.addCookies(to: &urlRequest)

        let userAgent = WKWebView().value(forKey: "userAgent") as? String

        let configuration = URLSessionConfiguration.default
        if let userAgent {
            configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        }
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let (data, response) = try? await session.data(for: urlRequest),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            return nil
        }

        return providerType.parseAccountInfo(from: data)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
