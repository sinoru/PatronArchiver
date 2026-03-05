import Foundation
import WebKit

extension WKWebsiteDataStore {
    func cookies(for url: URL) async -> [HTTPCookie] {
        let allCookies = await httpCookieStore.allCookies()
        guard let host = url.host() else { return [] }
        return allCookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host.hasSuffix(domain)
        }
    }

    func urlRequest(for url: URL) async -> URLRequest {
        var request = URLRequest(url: url)
        let cookies = await cookies(for: url)
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
