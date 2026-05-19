import Foundation

struct SubscribeStarAdultProvider: SubscribeStarProviding {
    static let baseURL = URL(string: "https://subscribestar.adult")!
    static let siteIdentifier = "SubscribeStar.adult"

    nonisolated(unsafe) static let matchPatterns: [Regex<Substring>] = [
        /https:\/\/subscribestar\.adult\/posts\/.+/,
    ]
}
