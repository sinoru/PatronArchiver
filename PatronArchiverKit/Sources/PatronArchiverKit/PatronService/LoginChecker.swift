import Foundation
import WebKit

public enum LoginChecker {
    /// Checks login status by making an HTTP request to the provider's accountCheckURL
    /// using cookies from the WKWebsiteDataStore.
    ///
    /// - Returns: The account info if logged in, nil otherwise.
    public static func check(
        for providerType: any PatronServiceProvider.Type,
        dataStore: WKWebsiteDataStore
    ) async -> AccountInfo? {
        let url = providerType.accountCheckURL
        let request = await dataStore.urlRequest(for: url)

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let (data, response) = try? await session.data(for: request),
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
