import Foundation
import OSLog
import WebKit

@MainActor
@Observable
class PatronArchiver {
    private static let logger = Logger(subsystem: "com.sinoru.PatronArchiver", category: "PatronArchiver")
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
        discardPendingSaveIfNeeded(job)
        if !job.status.isTerminal {
            job.status = .failed(CancellationError())
        }
    }

    func removeJob(_ job: ArchiveJob) {
        cancelJob(job)
        jobs.removeAll { $0.id == job.id }
    }

    func retryJob(_ job: ArchiveJob) {
        discardPendingSaveIfNeeded(job)
        job.status = .queued
        job.progress = 0
        job.metadata = nil
        job.mediaItems = []
        startJobIfPossible(job)
    }

    private func discardPendingSaveIfNeeded(_ job: ArchiveJob) {
        if let preparedSave = job.pendingSave {
            StorageManager.discardPreparedSave(preparedSave)
            job.pendingSave = nil
        }
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
            // 1. Identify service provider
            Self.logger.info("Starting job for URL: \(job.inputURL, privacy: .private)")
            guard let provider = PatronServiceManager.shared.provider(for: job.inputURL) else {
                throw JobError.unsupportedSite
            }
            Self.logger.info("Matched provider: \(type(of: provider).siteIdentifier, privacy: .public)")

            // 2. Load page
            job.status = .loading
            job.progress = 0.1
            let tracker = RedirectTracker()
            Self.logger.debug("Loading page...")
            let redirectChain = try await tracker.load(job.inputURL, in: webView)
            Self.logger.debug("Page loaded, redirect chain count: \(redirectChain.count)")

            // 3. Check login
            let isLoggedIn = try await provider.checkLoginStatus(in: webView)
            Self.logger.info("Login status: \(isLoggedIn)")
            if !isLoggedIn {
                throw JobError.loginRequired(type(of: provider).siteIdentifier)
            }

            // 4. Preload
            job.status = .preloading
            job.progress = 0.2
            Self.logger.debug("Preloading...")
            try await Preloader.preload(in: webView, scrollDelay: settings.scrollDelay)
            try await provider.preloadContent(in: webView)
            Self.logger.debug("Preload complete")
            job.progress = 0.3

            // 5. Extract metadata
            Self.logger.debug("Extracting metadata...")
            var metadata = try await provider.extractMetadata(in: webView)
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
            let pageTitle = webView.title ?? metadata.title
            Self.logger.info("Metadata extracted — title: \(metadata.title, privacy: .private), author: \(metadata.authorName, privacy: .private), pageTitle: \(pageTitle, privacy: .private)")

            // 6. Extract media URLs
            let mediaItems = try await provider.extractMediaURLs(in: webView)
            job.mediaItems = mediaItems
            job.progress = 0.4
            Self.logger.info("Found \(mediaItems.count) media items")

            // 7. Page dump (MHTML first to preserve original HTML, then PDF)
            job.status = .dumping

            Self.logger.debug("Generating MHTML...")
            let mhtmlData = try await webView.mhtml(dataStore: webViewPool.sharedDataStore)
            Self.logger.debug("MHTML generated (\(mhtmlData.count) bytes)")
            job.progress = 0.5

            Self.logger.debug("Generating PDF...")
            let pdfData = try await webView.fullPagePDF()
            Self.logger.debug("PDF generated (\(pdfData.count) bytes)")
            job.progress = 0.6

            // 8. Download media
            job.status = .downloading
            Self.logger.debug("Downloading media...")
            let tempDir = try StorageManager.temporaryDownloadDirectory()
            let downloadedMedia = try await MediaDownloader.download(
                items: mediaItems,
                to: tempDir,
                dataStore: webViewPool.sharedDataStore
            )
            Self.logger.info("Downloaded \(downloadedMedia.count) media files")
            job.progress = 0.8

            // 9. Prepare save (write PDF/MHTML to staging + xattr)
            job.status = .saving
            let baseDir = resolveBaseDirectory()
            Self.logger.debug("Preparing save to: \(baseDir.path(), privacy: .private)")
            let preparedSave = try StorageManager.prepareSave(
                metadata: metadata,
                pageTitle: pageTitle,
                pdfData: pdfData,
                mhtmlData: mhtmlData,
                downloadedMedia: downloadedMedia,
                stagingDirectory: tempDir,
                baseDirectory: baseDir
            )
            job.progress = 0.9

            // 10. Check if post folder already exists
            let folderExists = BookmarkManager.withAccess(to: baseDir) {
                StorageManager.postFolderExists(metadata: metadata, baseDirectory: baseDir)
            }

            if folderExists {
                // Await user confirmation
                Self.logger.info("Post folder already exists, awaiting overwrite confirmation")
                job.pendingSave = preparedSave
                job.status = .awaitingOverwriteConfirmation
                return
            }

            // 11. Commit save
            try BookmarkManager.withAccess(to: baseDir) {
                try StorageManager.commitSave(preparedSave, overwrite: false)
            }
            job.progress = 1.0
            job.status = .completed
            Self.logger.info("Job completed successfully")
        } catch {
            Self.logger.error("Job failed: \(error.localizedDescription, privacy: .public)")
            job.status = .failed(error)
        }
    }

    func confirmOverwrite(_ job: ArchiveJob) {
        guard let preparedSave = job.pendingSave else { return }
        job.status = .saving

        do {
            let baseDir = resolveBaseDirectory()
            try BookmarkManager.withAccess(to: baseDir) {
                try StorageManager.commitSave(preparedSave, overwrite: true)
            }
            job.pendingSave = nil
            job.progress = 1.0
            job.status = .completed
            Self.logger.info("Overwrite confirmed and save committed")
        } catch {
            job.pendingSave = nil
            Self.logger.error("Overwrite commit failed: \(error.localizedDescription, privacy: .public)")
            job.status = .failed(error)
        }
    }

    func skipOverwrite(_ job: ArchiveJob) {
        if let preparedSave = job.pendingSave {
            StorageManager.discardPreparedSave(preparedSave)
        }
        job.pendingSave = nil
        job.status = .failed(JobError.overwriteDeclined)
        Self.logger.info("Overwrite declined, staging discarded")
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
    case overwriteDeclined

    var errorDescription: String? {
        switch self {
        case .unsupportedSite:
            "This site is not supported."
        case .loginRequired(let site):
            "Login required for \(site)."
        case .overwriteDeclined:
            "Overwrite declined by user."
        }
    }
}
