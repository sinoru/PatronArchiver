import Foundation

struct MediaItem: Sendable {
    let url: URL
    let type: MediaType
    let filename: String?
    let referrerURL: URL?
}

enum MediaType: Sendable {
    case image
    case video
    case audio
    case archive
    case game
    case other
}
