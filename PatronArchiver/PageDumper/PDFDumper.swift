import WebKit

enum PDFDumper {
    static func createPDF(from webView: WKWebView) async throws -> Data {
        let contentHeight = try await webView.evaluateJavaScript(
            "document.documentElement.scrollHeight"
        ) as? Double ?? 0

        let config = WKPDFConfiguration()
        config.rect = CGRect(
            x: 0,
            y: 0,
            width: webView.frame.width,
            height: contentHeight
        )

        return try await webView.pdf(configuration: config)
    }
}
