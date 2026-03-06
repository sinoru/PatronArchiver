import Foundation
import WebKit

extension WKWebsiteDataStore {
    func cookies(for url: URL) async -> [HTTPCookie] {
        let allCookies = await httpCookieStore.allCookies()
        guard let host = url.host() else { return [] }
        return allCookies.filter { cookie in
            if cookie.domain.hasPrefix(".") {
                let domain = String(cookie.domain.dropFirst())
                return host == domain || host.hasSuffix("." + domain)
            } else {
                return host == cookie.domain
            }
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
