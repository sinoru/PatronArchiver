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

    init(_ string: String?) {
        self = switch string {
        case "image": .image
        case "video": .video
        case "audio": .audio
        case "archive": .archive
        case "game": .game
        default: .other
        }
    }
}

extension MediaItem {
    init?(from dictionary: [String: Any], referrerURL: URL?) {
        guard let urlString = dictionary["url"] as? String,
              let url = URL(string: urlString)
        else { return nil }
        self.init(
            url: url,
            type: MediaType(dictionary["type"] as? String),
            filename: dictionary["filename"] as? String,
            referrerURL: referrerURL
        )
    }
}
