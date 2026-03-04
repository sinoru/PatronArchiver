import Foundation
import WebKit

enum CookieHelper {
    static func cookies(from dataStore: WKWebsiteDataStore, for url: URL) async -> [HTTPCookie] {
        let allCookies = await dataStore.httpCookieStore.allCookies()
        guard let host = url.host() else { return [] }
        return allCookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host.hasSuffix(domain)
        }
    }

    static func configuredRequest(for url: URL, dataStore: WKWebsiteDataStore) async -> URLRequest {
        var request = URLRequest(url: url)
        let cookies = await cookies(from: dataStore, for: url)
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
