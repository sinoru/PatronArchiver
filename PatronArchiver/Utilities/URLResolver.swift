import Foundation
import os

struct URLResolver: Sendable {
    private static let logger = Logger(
        subsystem: "com.sinoru.PatronArchiver",
        category: "URLResolver"
    )

    static func resolve(_ url: URL, timeout: TimeInterval = 10) async -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let resolvedURL = httpResponse.url {
                logger.debug("Resolved \(url.absoluteString, privacy: .private) → \(resolvedURL.absoluteString, privacy: .private)")
                return resolvedURL
            }
        } catch {
            logger.warning("Failed to resolve \(url.absoluteString, privacy: .private): \(error.localizedDescription)")
        }

        return url
    }
}
