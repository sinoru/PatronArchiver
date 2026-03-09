import Foundation

@MainActor
@Observable
public final class ArchiveJob: Identifiable {
    public let id: UUID
    public let inputURL: URL
    public let provider: (any PatronServiceProvider)?
    public internal(set) var status: JobStatus
    public internal(set) var metadata: PostMetadata?
    var mediaItems: [MediaItem]
    public internal(set) var progress: Progress
    var pendingSave: StorageManager.PreparedSave?

    init(id: UUID = UUID(), inputURL: URL, provider: (any PatronServiceProvider)? = nil) {
        self.id = id
        self.inputURL = inputURL
        self.provider = provider
        self.status = .queued
        self.metadata = nil
        self.mediaItems = []
        self.progress = Progress(totalUnitCount: 100)
        self.pendingSave = nil
    }
}

public enum JobStatus {
    case queued
    case loading
    case preloading
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
        case .loading, .preloading, .dumping, .downloading, .saving: true
        default: false
        }
    }

    public var displayName: LocalizedStringResource {
        switch self {
        case .queued: .init("Queued", bundle: .forClass(PatronArchiver.self))
        case .loading: .init("Loading", bundle: .forClass(PatronArchiver.self))
        case .preloading: .init("Preloading", bundle: .forClass(PatronArchiver.self))
        case .dumping: .init("Dumping", bundle: .forClass(PatronArchiver.self))
        case .downloading: .init("Downloading", bundle: .forClass(PatronArchiver.self))
        case .saving: .init("Saving", bundle: .forClass(PatronArchiver.self))
        case .awaitingOverwriteConfirmation: .init("Folder Exists", bundle: .forClass(PatronArchiver.self))
        case .completed: .init("Completed", bundle: .forClass(PatronArchiver.self))
        case .failed: .init("Failed", bundle: .forClass(PatronArchiver.self))
        }
    }
}
