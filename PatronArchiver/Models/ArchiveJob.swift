import Foundation

@Observable
class ArchiveJob: Identifiable {
    let id: UUID
    let inputURL: URL
    var status: JobStatus
    var metadata: PostMetadata?
    var mediaItems: [MediaItem]
    var progress: Double
    var pendingSave: StorageManager.PreparedSave?

    init(id: UUID = UUID(), inputURL: URL) {
        self.id = id
        self.inputURL = inputURL
        self.status = .queued
        self.metadata = nil
        self.mediaItems = []
        self.progress = 0
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
