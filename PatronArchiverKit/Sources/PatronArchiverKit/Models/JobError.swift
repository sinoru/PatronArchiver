import Foundation

enum JobError: LocalizedError {
    case unsupportedSite
    case overwriteDeclined

    var errorDescription: String? {
        switch self {
        case .unsupportedSite:
            "This site is not supported."
        case .overwriteDeclined:
            "Overwrite declined by user."
        }
    }
}
