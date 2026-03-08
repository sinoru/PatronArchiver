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

    public func addCookies(to urlRequest: inout URLRequest) async {
        guard let url = urlRequest.url else { return }

        let cookies = await cookies(for: url)
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
    }
}
