import Foundation
import WebKit

extension WKWebView {
    /// Generates a full-page-height PDF of the current page.
    ///
    /// - Returns: The PDF data.
    func fullPagePDF() async throws -> Data {
        let contentHeight = try await evaluateJavaScript(
            "document.documentElement.scrollHeight"
        ) as? Double ?? 0

        let config = WKPDFConfiguration()
        config.rect = CGRect(
            x: 0,
            y: 0,
            width: frame.width,
            height: contentHeight
        )

        return try await pdf(configuration: config)
    }
}
