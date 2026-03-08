import Foundation

public struct PatronServiceManager: Sendable {
    public static let allProviderTypes: [any PatronServiceProvider.Type] = [
        PatreonProvider.self,
        PixivFanboxProvider.self,
    ]

    static let shared = PatronServiceManager()

    private init() {}

    func provider(for url: URL) -> (any PatronServiceProvider)? {
        let urlString = url.absoluteString
        for providerType in Self.allProviderTypes {
            for pattern in providerType.matchPatterns {
                if Self.wholeMatch(urlString, pattern: pattern) {
                    return providerType.init()
                }
            }
        }
        return nil
    }

    private static func wholeMatch(_ string: String, pattern: some RegexComponent) -> Bool {
        string.wholeMatch(of: pattern) != nil
    }
}
