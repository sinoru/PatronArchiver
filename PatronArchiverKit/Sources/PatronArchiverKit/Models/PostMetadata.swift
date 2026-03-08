import Foundation

public struct PostMetadata: Sendable {
    public let siteIdentifier: String
    public let postID: String
    public let title: String
    public let authorName: String
    public let createdAt: Date
    public let modifiedAt: Date?
    public let tags: [String]
    public let originalURL: URL
    public let redirectChain: [URL]

    public var displayDate: Date {
        modifiedAt ?? createdAt
    }
}
