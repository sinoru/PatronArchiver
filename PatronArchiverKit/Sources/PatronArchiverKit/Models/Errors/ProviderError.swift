import Foundation

enum ProviderError: LocalizedError {
    case metadataExtractionFailed
    case mediaExtractionFailed

    var errorDescription: String? {
        switch self {
        case .metadataExtractionFailed:
            String(localized: "Failed to extract metadata.", bundle: Bundle.module)
        case .mediaExtractionFailed:
            String(localized: "Failed to extract media.", bundle: Bundle.module)
        }
    }
}
