import Foundation
import OSLog
import WebKit
#if os(iOS)
@preconcurrency import BackgroundTasks
#endif

@MainActor
@Observable
public class PatronArchiver {
    private static let logger = Logger(subsystem: Logger.moduleSubsystem, category: "PatronArchiver")
    public private(set) var jobs: [ArchiveJob] = []
    public var webView: WKWebView? {
        didSet { processNextQueuedJob() }
    }
    public var settings = AppSettings()
    public let websiteDataStore = WKWebsiteDataStore.default()
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

#if os(iOS)
    private static let bgTaskIdentifier = "dev.sinoru.PatronArchiver.archive"
    private var activeBGTask: BGContinuedProcessingTask?
    private var bgProgressObservation: NSKeyValueObservation?
#endif

#if os(macOS)
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
#else
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
#endif

    public var renderSize: CGSize {
        CGSize(width: CGFloat(settings.renderWidth), height: 1080)
    }

    public init() { }
}

extension PatronArchiver {
    public func enqueue(url: URL) {
        let provider = PatronServiceManager.shared.provider(for: url)
        let job = ArchiveJob(inputURL: url, provider: provider)
        jobs.append(job)
        startJobIfPossible(job)
    }

    public func cancelJob(_ job: ArchiveJob) {
        activeTasks[job.id]?.cancel()
        activeTasks[job.id] = nil
        discardPendingSaveIfNeeded(job)
        if !job.status.isTerminal {
            job.status = .failed(CancellationError())
        }
        processNextQueuedJob()
    }

    public func removeJob(_ job: ArchiveJob) {
        cancelJob(job)
        jobs.removeAll { $0.id == job.id }
    }

    public func retryJob(_ job: ArchiveJob) {
        discardPendingSaveIfNeeded(job)
        job.status = .queued
        job.progress = Progress(totalUnitCount: 100)
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
        guard activeTasks.isEmpty, webView != nil else { return }

        let task = Task {
            await processJob(job)
        }
        activeTasks[job.id] = task

        #if os(iOS)
        if activeBGTask == nil {
            submitBackgroundTask(for: job)
        } else if let bgTask = activeBGTask {
            observeJobProgress(job, for: bgTask)
        }
        #endif
    }

    private func processJob(_ job: ArchiveJob) async {
        guard let webView else { return }

        do {
            // 1. Identify service provider
            Self.logger.info("Starting job for URL: \(job.inputURL, privacy: .private)")
            guard let provider = job.provider else {
                throw JobError.unsupportedSite
            }
            Self.logger.info("Matched provider: \(type(of: provider).siteIdentifier, privacy: .public)")

            // 2. Load page
            job.status = .loading
            job.progress.completedUnitCount = 10
            try Task.checkCancellation()
            let tracker = RedirectTracker()
            Self.logger.debug("Loading page...")
            let redirectChain = try await tracker.load(job.inputURL, in: webView)
            let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
            Self.logger.debug("Page loaded, redirect chain: \(redirectChain.map(\.absoluteString), privacy: .private)")

            // 3. Check login
            let isLoggedIn = try await provider.checkLoginStatus(in: webView)
            Self.logger.info("Login status: \(isLoggedIn)")
            if !isLoggedIn {
                throw JobError.loginRequired(type(of: provider).siteIdentifier)
            }

            // 4. Load lazy content
            try Task.checkCancellation()
            job.status = .preloading
            job.progress.completedUnitCount = 20
            Self.logger.debug("Loading lazy content...")
            try await webView.loadLazyContent(scrollDelay: settings.scrollDelay)
            try await provider.preloadContent(in: webView)
            try await webView.loadLazyContent(scrollDelay: settings.scrollDelay)
            Self.logger.debug("Lazy content loaded")
            job.progress.completedUnitCount = 30

            // 5. Extract metadata
            try Task.checkCancellation()
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
            job.progress.completedUnitCount = 40
            Self.logger.info("Found \(mediaItems.count) media items")

            // 7. Page dump + media download (concurrent)
            try Task.checkCancellation()
            job.status = .dumping

            let tempDir = try StorageManager.temporaryDownloadDirectory()

            // Start media download in background (no WebView dependency)
            Self.logger.debug("Starting media download concurrently...")
            let totalMedia = mediaItems.count
            let completedMediaCount = OSAllocatedUnfairLock(initialState: 0)
            async let mediaResult = MediaDownloader.download(
                items: mediaItems,
                to: tempDir,
                websiteDataStore: websiteDataStore,
                userAgent: userAgent,
                onFileDownloaded: { @Sendable in
                    let count = completedMediaCount.withLock { value in
                        value += 1
                        return value
                    }
                    Task { @MainActor in
                        guard job.progress.completedUnitCount >= 60 else { return }
                        job.progress.completedUnitCount = 60 + Int64(count * 20 / max(totalMedia, 1))
                    }
                }
            )

            // MHTML + PDF on WebView (sequential, needs WebView)
            Self.logger.debug("Generating MHTML...")
            let mhtmlData = try await MHTMLArchiver(webView).archive()
            Self.logger.debug("MHTML generated (\(mhtmlData.count.formatted(.byteCount(style: .binary, spellsOutZero: false, includesActualByteCount: true))))")
            job.progress.completedUnitCount = 50

            Self.logger.debug("Generating PDF...")
            let pdfData = try await webView.fullPagePDF()
            Self.logger.debug("PDF generated (\(pdfData.count.formatted(.byteCount(style: .binary, spellsOutZero: false, includesActualByteCount: true))))")
            let alreadyCompleted = completedMediaCount.withLock { $0 }
            job.progress.completedUnitCount = 60 + Int64(alreadyCompleted * 20 / max(totalMedia, 1))

            // Await media download completion
            let downloadedMedia = try await mediaResult
            Self.logger.info("Downloaded \(downloadedMedia.count) media files")
            job.progress.completedUnitCount = 80

            // 9. Prepare save (write PDF/MHTML to staging + xattr)
            try Task.checkCancellation()
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
                baseDirectory: baseDir,
                includesWhereFroms: settings.includesWhereFroms,
                includesFinderTags: settings.includesFinderTags
            )
            job.progress.completedUnitCount = 90

            // 10. Check if post folder already exists
            let folderExists = try baseDir.withSecurityScopedAccess {
                try StorageManager.postFolderExists(metadata: metadata, baseDirectory: baseDir)
            }

            if folderExists {
                // Await user confirmation
                Self.logger.info("Post folder already exists, awaiting overwrite confirmation")
                job.pendingSave = preparedSave
                job.status = .awaitingOverwriteConfirmation
                return
            }

            // 11. Commit save
            try baseDir.withSecurityScopedAccess {
                try StorageManager.commitSave(preparedSave, overwrite: false)
            }
            job.progress.completedUnitCount = 100
            job.status = .completed
            Self.logger.info("Job completed successfully")
        } catch {
            Self.logger.error("Job failed: \(error.localizedDescription, privacy: .public)")
            job.status = .failed(error)
        }

        await loadBlankPage(in: webView)
        activeTasks[job.id] = nil
        processNextQueuedJob()
    }

    private func loadBlankPage(in webView: WKWebView) async {
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        guard webView.isLoading else { return }
        for await isLoading in webView.publisher(for: \.isLoading)
            .buffer(size: .max, prefetch: .byRequest, whenFull: .dropOldest)
            .values
        {
            if !isLoading {
                break
            }
        }
    }

    public func confirmOverwrite(_ job: ArchiveJob) {
        guard let preparedSave = job.pendingSave else { return }
        job.status = .saving

        do {
            let baseDir = resolveBaseDirectory()
            try baseDir.withSecurityScopedAccess {
                try StorageManager.commitSave(preparedSave, overwrite: true)
            }
            job.pendingSave = nil
            job.progress.completedUnitCount = 100
            job.status = .completed
            Self.logger.info("Overwrite confirmed and save committed")
        } catch {
            job.pendingSave = nil
            Self.logger.error("Overwrite commit failed: \(error.localizedDescription, privacy: .public)")
            job.status = .failed(error)
        }
    }

    public func skipOverwrite(_ job: ArchiveJob) {
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
        }) else {
            #if os(iOS)
            completeBackgroundTaskIfNeeded()
            #endif
            return
        }
        startJobIfPossible(nextJob)
    }

    // MARK: - iOS Background Task

    #if os(iOS)
    private func submitBackgroundTask(for job: ArchiveJob) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskIdentifier, using: .main) { [weak self] bgTask in
            guard let bgTask = bgTask as? BGContinuedProcessingTask else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.activeBGTask = bgTask
                bgTask.progress.totalUnitCount = 100
                self.observeJobProgress(job, for: bgTask)

                bgTask.expirationHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        for (_, task) in self.activeTasks {
                            task.cancel()
                        }
                        self.bgProgressObservation?.invalidate()
                        self.bgProgressObservation = nil
                        self.activeBGTask?.setTaskCompleted(success: false)
                        self.activeBGTask = nil
                    }
                }
            }
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: String(localized: "Archiving Post"),
            subtitle: job.inputURL.host() ?? ""
        )

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.error("Failed to submit continued processing task: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeJobProgress(_ job: ArchiveJob, for bgTask: BGContinuedProcessingTask) {
        bgProgressObservation?.invalidate()
        bgProgressObservation = job.progress.observe(\.completedUnitCount, options: [.new]) { [weak bgTask] progress, _ in
            bgTask?.progress.completedUnitCount = progress.completedUnitCount
        }
    }

    private func completeBackgroundTaskIfNeeded() {
        bgProgressObservation?.invalidate()
        bgProgressObservation = nil
        activeBGTask?.setTaskCompleted(success: true)
        activeBGTask = nil
    }
    #endif

    private func resolveBaseDirectory() -> URL {
        var isStale = false
        if let bookmarkData = settings.savedDirectoryBookmark,
           let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: Self.bookmarkResolutionOptions,
            bookmarkDataIsStale: &isStale
           ) {
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
