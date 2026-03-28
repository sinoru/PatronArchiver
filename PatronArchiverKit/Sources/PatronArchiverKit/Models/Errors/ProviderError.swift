import Foundation

enum ProviderError: LocalizedError {
    case metadataExtractionFailed
    case mediaExtractionFailed

    var errorDescription: String? {
        switch self {
        case .metadataExtractionFailed: "Failed to extract metadata."
        case .mediaExtractionFailed: "Failed to extract media."
        }
    }
}
