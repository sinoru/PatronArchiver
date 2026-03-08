import Foundation

public struct MediaItem: Sendable {
    public let url: URL
    public let type: MediaType
    public let filename: String?
    public let referrerURL: URL?
}

public enum MediaType: Sendable {
    case image
    case video
    case audio
    case archive
    case game
    case other
}
