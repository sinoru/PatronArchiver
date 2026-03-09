import WebKit

extension WKWebView {
    func loadLazyContent(scrollDelay: Double = 150) async throws {
        guard let script = String(bytes: PackageResources.LazyContentLoader_js, encoding: .utf8) else {
            fatalError("Failed to decode LazyContentLoader.js as UTF-8")
        }

        _ = try await callAsyncJavaScript(
            script,
            arguments: ["delay": scrollDelay],
            contentWorld: .page
        )
    }
}
