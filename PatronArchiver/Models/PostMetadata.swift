import Foundation

struct PostMetadata: Sendable {
    let siteIdentifier: String
    let postID: String
    let title: String
    let authorName: String
    let createdAt: Date
    let modifiedAt: Date?
    let tags: [String]
    let originalURL: URL
    let redirectChain: [URL]

    var displayDate: Date {
        modifiedAt ?? createdAt
    }
}
