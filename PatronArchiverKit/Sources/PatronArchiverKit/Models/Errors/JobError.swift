import Foundation

enum JobError: LocalizedError {
    case unsupportedSite
    case overwriteDeclined

    var errorDescription: String? {
        switch self {
        case .unsupportedSite:
            String(localized: "This site is not supported.", bundle: Bundle.module)
        case .overwriteDeclined:
            String(localized: "Replace declined by user.", bundle: Bundle.module)
        }
    }
}
