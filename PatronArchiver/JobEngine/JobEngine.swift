import Foundation
import WebKit

@Observable
class JobEngine {
    private(set) var jobs: [ArchiveJob] = []
    private let webViewPool: WebViewPool
    private let settings: AppSettings
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        self.webViewPool = WebViewPool(
            poolSize: settings.maxConcurrentJobs,
            renderWidth: CGFloat(settings.renderWidth)
        )
    }

    func enqueue(url: URL) {
        let job = ArchiveJob(inputURL: url)
        jobs.append(job)
        startJobIfPossible(job)
    }

    func cancelJob(_ job: ArchiveJob) {
        activeTasks[job.id]?.cancel()
        activeTasks[job.id] = nil
        if !job.status.isTerminal {
            job.status = .failed(CancellationError())
        }
    }

    func removeJob(_ job: ArchiveJob) {
        cancelJob(job)
        jobs.removeAll { $0.id == job.id }
    }

    func retryJob(_ job: ArchiveJob) {
        job.status = .queued
        job.progress = 0
        job.metadata = nil
        job.mediaItems = []
        startJobIfPossible(job)
    }

    private func startJobIfPossible(_ job: ArchiveJob) {
        let activeCount = activeTasks.count
        guard activeCount < settings.maxConcurrentJobs else { return }

        let task = Task {
            await processJob(job)
        }
        activeTasks[job.id] = task
    }

    private func processJob(_ job: ArchiveJob) async {
        let webView = await webViewPool.acquire()
        defer {
            webViewPool.release(webView)
            activeTasks[job.id] = nil
            processNextQueuedJob()
        }

        do {
            // 1. Identify site plugin
            guard let plugin = SitePluginRegistry.shared.plugin(for: job.inputURL) else {
                throw JobError.unsupportedSite
            }

            // 2. Load page
            job.status = .loading
            job.progress = 0.1
            let tracker = RedirectTracker()
            let redirectChain = try await tracker.load(job.inputURL, in: webView)

            // 3. Check login
            let isLoggedIn = try await plugin.checkLoginStatus(in: webView)
            if !isLoggedIn {
                throw JobError.loginRequired(type(of: plugin).siteIdentifier)
            }

            // 4. Preload
            job.status = .preloading
            job.progress = 0.2
            try await Preloader.preload(in: webView, scrollDelay: settings.scrollDelay)
            try await plugin.preloadContent(in: webView)
            job.progress = 0.3

            // 5. Extract metadata
            var metadata = try await plugin.extractMetadata(in: webView)
            metadata = PostMetadata(
                siteIdentifier: metadata.siteIdentifier,
                postID: metadata.postID,
                title: metadata.title,
                authorName: metadata.authorName,
                createdAt: metadata.createdAt,
                modifiedAt: metadata.modifiedAt,
                tags: metadata.tags,
                originalURL: metadata.originalURL,
                redirectChain: redirectChain
            )
            job.metadata = metadata

            // 6. Extract media URLs
            let mediaItems = try await plugin.extractMediaURLs(in: webView)
            job.mediaItems = mediaItems
            job.progress = 0.4

            // 7. Page dump (PDF → MHTML, sequential)
            job.status = .dumping
            let pdfData = try await PDFDumper.createPDF(from: webView)
            job.progress = 0.5

            let mhtmlData = try await MHTMLDumper.createMHTML(
                from: webView,
                dataStore: webViewPool.sharedDataStore
            )
            job.progress = 0.6

            // 8. Download media
            job.status = .downloading
            let tempDir = try StorageManager.temporaryDownloadDirectory()
            let downloadedMedia = try await MediaDownloader.download(
                items: mediaItems,
                to: tempDir,
                dataStore: webViewPool.sharedDataStore
            )
            job.progress = 0.8

            // 9. Save
            job.status = .saving
            let baseDir = resolveBaseDirectory()
            try await BookmarkManager.withAccess(to: baseDir) {
                try StorageManager.save(
                    metadata: metadata,
                    pdfData: pdfData,
                    mhtmlData: mhtmlData,
                    downloadedMedia: downloadedMedia,
                    to: baseDir
                )
            }
            job.progress = 1.0
            job.status = .completed
        } catch {
            job.status = .failed(error)
        }
    }

    private func processNextQueuedJob() {
        guard let nextJob = jobs.first(where: {
            if case .queued = $0.status { return true }
            return false
        }) else { return }
        startJobIfPossible(nextJob)
    }

    private func resolveBaseDirectory() -> URL {
        if let bookmarkData = settings.savedDirectoryBookmark,
           let url = try? BookmarkManager.resolveBookmark(bookmarkData) {
            return url
        }
        return settings.defaultSaveDirectory
    }
}

enum JobError: LocalizedError {
    case unsupportedSite
    case loginRequired(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSite:
            "This site is not supported."
        case .loginRequired(let site):
            "Login required for \(site)."
        }
    }
}
