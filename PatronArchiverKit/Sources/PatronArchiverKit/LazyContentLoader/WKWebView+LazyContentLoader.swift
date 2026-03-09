import WebKit

extension WKWebView {
    func loadLazyContent(scrollDelay: Double = 150) async throws {
        guard let scriptURL = Bundle.module.url(forResource: "LazyContentLoader", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fatalError("LazyContentLoader.js not found in bundle")
        }

        _ = try await callAsyncJavaScript(
            script,
            arguments: ["delay": scrollDelay],
            contentWorld: .page
        )
    }
}
