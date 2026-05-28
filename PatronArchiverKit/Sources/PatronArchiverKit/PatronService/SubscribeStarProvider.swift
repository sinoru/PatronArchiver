import Foundation

struct SubscribeStarProvider: SubscribeStarProviding {
    static let baseURL = URL(string: "https://www.subscribestar.com")!
    static let siteIdentifier = "SubscribeStar"

    nonisolated(unsafe) static let matchPatterns: [Regex<Substring>] = [
        /https:\/\/(?:www\.)?subscribestar\.com\/posts\/.+/,
    ]

    static let alternateProviderType: (any PatronServiceProviding.Type)? = SubscribeStarAdultProvider.self
}
