import Foundation

public enum JobStatus {
    case queued
    case loading
    case dumping
    case downloading
    case saving
    case awaitingOverwriteConfirmation
    case completed
    case failed(Error)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: true
        default: false
        }
    }

    public var isInProgress: Bool {
        switch self {
        case .loading, .dumping, .downloading, .saving: true
        default: false
        }
    }

    public var displayName: LocalizedStringResource {
        switch self {
        case .queued: .init("Queued", bundle: .forClass(PatronArchiver.self))
        case .loading: .init("Loading", bundle: .forClass(PatronArchiver.self))
        case .dumping: .init("Dumping", bundle: .forClass(PatronArchiver.self))
        case .downloading: .init("Downloading", bundle: .forClass(PatronArchiver.self))
        case .saving: .init("Saving", bundle: .forClass(PatronArchiver.self))
        case .awaitingOverwriteConfirmation: .init("Folder Exists", bundle: .forClass(PatronArchiver.self))
        case .completed: .init("Completed", bundle: .forClass(PatronArchiver.self))
        case .failed: .init("Failed", bundle: .forClass(PatronArchiver.self))
        }
    }
}
