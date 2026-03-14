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
