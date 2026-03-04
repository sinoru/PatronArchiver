import WebKit

class RedirectTracker: NSObject, WKNavigationDelegate {
    private(set) var redirectChain: [URL] = []
    private var continuation: CheckedContinuation<[URL], any Error>?

    func load(_ url: URL, in webView: WKWebView) async throws -> [URL] {
        redirectChain = [url]
        webView.navigationDelegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url,
           navigationAction.navigationType == .other || navigationAction.targetFrame?.isMainFrame == true {
            await MainActor.run {
                if redirectChain.last != url {
                    redirectChain.append(url)
                }
            }
        }
        return .allow
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            if let finalURL = webView.url, redirectChain.last != finalURL {
                redirectChain.append(finalURL)
            }
            let chain = redirectChain
            continuation?.resume(returning: chain)
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
