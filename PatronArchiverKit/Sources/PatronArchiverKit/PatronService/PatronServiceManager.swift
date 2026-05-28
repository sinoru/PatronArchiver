import Foundation

public struct PatronServiceManager: Sendable {
    /// Providers shown in the user-facing site list (e.g., Settings).
    public static let userVisibleProviderTypes: [any PatronServiceProviding.Type] = [
        PatreonProvider.self,
        PixivFanboxProvider.self,
        SubscribeStarProvider.self,
    ]

    /// All providers, including alternates that are reachable via URL routing
    /// but should not be listed in the user-facing UI.
    public static let allProviderTypes: [any PatronServiceProviding.Type] = userVisibleProviderTypes
        + [SubscribeStarAdultProvider.self]

    static let shared = PatronServiceManager()

    private init() {}

    func provider(for url: URL) -> (any PatronServiceProviding)? {
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

    private static func wholeMatch(_ string: String, pattern: Regex<Substring>) -> Bool {
        string.wholeMatch(of: pattern) != nil
    }
}
