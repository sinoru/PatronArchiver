import Foundation

@Observable
class ArchiveJob: Identifiable {
    let id: UUID
    let inputURL: URL
    let provider: (any PatronServiceProvider)?
    var status: JobStatus
    var metadata: PostMetadata?
    var mediaItems: [MediaItem]
    var progress: Progress
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

enum JobStatus {
    case queued
    case loading
    case preloading
    case dumping
    case downloading
    case saving
    case awaitingOverwriteConfirmation
    case completed
    case failed(Error)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .loading: "Loading"
        case .preloading: "Preloading"
        case .dumping: "Dumping"
        case .downloading: "Downloading"
        case .saving: "Saving"
        case .awaitingOverwriteConfirmation: "Folder Exists"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}
