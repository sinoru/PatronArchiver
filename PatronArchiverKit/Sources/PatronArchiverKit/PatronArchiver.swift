import Foundation
import OSLog
import WebKit

@MainActor
@Observable
public final class PatronArchiver {
    private static let logger = Logger(subsystem: Logger.moduleSubsystem, category: "PatronArchiver")
    public internal(set) var jobs: [ArchiveJob] = []
    public var webView: WKWebView? {
        didSet { processNextQueuedJob() }
    }
    public var settings = AppSettings()
    public let websiteDataStore = WKWebsiteDataStore.default()
    public let urlSession: URLSession
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    #if DEBUG
    public internal(set) var isDemoMode = false
    #endif

    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }()

    public var renderSize: CGSize {
        CGSize(width: CGFloat(settings.renderWidth), height: 1080)
    }

    public init() {
        let userAgent = WKWebView().value(forKey: "userAgent") as? String
        let configuration = URLSessionConfiguration.default
        if let userAgent {
            configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        }
        self.urlSession = URLSession(configuration: configuration)
    }
}

// MARK: - Login Check

extension PatronArchiver {
    /// Checks login status by examining cookies only — fast, no network request.
    public func isLoggedIn(for providerType: any PatronServiceProvider.Type) async -> Bool {
        let cookies = await websiteDataStore.httpCookieStore.allCookies()
        return providerType.isLoggedIn(cookies: cookies)
    }

    /// Fetches account info by making an HTTP request to the provider's accountCheckURL.
    ///
    /// - Returns: The account info if successfully fetched, nil otherwise.
    public func fetchAccountInfo(for providerType: any PatronServiceProvider.Type) async -> AccountInfo? {
        let url = providerType.accountCheckURL
        var urlRequest = URLRequest(url: url)
        await websiteDataStore.addCookies(to: &urlRequest)

        let delegate = NoRedirectDelegate()
        guard let (data, response) = try? await urlSession.data(for: urlRequest, delegate: delegate),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            return nil
        }

        return providerType.parseAccountInfo(from: data)
    }
}

// MARK: - Job Queue

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
        #if DEBUG
        guard !isDemoMode else { return }
        #endif
        guard activeTasks.isEmpty, webView != nil else { return }

        let task = Task {
            await processJob(job)
        }
        activeTasks[job.id] = task
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
            let chain = redirectChain.map(\.absoluteString)
            Self.logger.debug("Page loaded, redirect chain: \(chain, privacy: .private)")

            // 3. Check login
            let isLoggedIn = await self.isLoggedIn(for: type(of: provider))
            Self.logger.info("Login status for \(type(of: provider).siteIdentifier, privacy: .public): \(isLoggedIn)")

            // 4. Load lazy content
            try Task.checkCancellation()
            job.progress.completedUnitCount = 15
            Self.logger.debug("Loading lazy content...")
            try await webView.loadLazyContent(scrollDelay: settings.scrollDelay)
            job.progress.completedUnitCount = 20
            try await provider.preloadContent(in: webView)
            job.progress.completedUnitCount = 25
            try await webView.loadLazyContent(scrollDelay: settings.scrollDelay)
            Self.logger.debug("Lazy content loaded")
            job.progress.completedUnitCount = 30

            // 5. Extract metadata
            try Task.checkCancellation()
            Self.logger.debug("Resolving time zone...")
            let timeZone = try await provider.resolveTimeZone(in: webView)
            Self.logger.debug("Extracting metadata...")
            var metadata = try await provider.extractMetadata(in: webView, timeZone: timeZone)
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
            Self.logger.info("Metadata extracted — \(metadata.title, privacy: .private)")
            Self.logger.info("  author: \(metadata.authorName, privacy: .private)")

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
                urlSession: urlSession,
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
            let mhtmlData = try await MHTMLArchiver(webView, urlSession: urlSession).archive()
            let mhtmlSize = mhtmlData.count.formatted(
                .byteCount(style: .binary, spellsOutZero: false, includesActualByteCount: true)
            )
            Self.logger.debug("MHTML generated (\(mhtmlSize))")
            job.progress.completedUnitCount = 50

            Self.logger.debug("Generating PDF...")
            let pdfData = try await webView.fullPagePDF()
            let pdfSize = pdfData.count.formatted(
                .byteCount(style: .binary, spellsOutZero: false, includesActualByteCount: true)
            )
            Self.logger.debug("PDF generated (\(pdfSize))")
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
                includesFinderTags: settings.includesFinderTags,
                includesContentDates: settings.includesContentDates
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
        }) else { return }
        startJobIfPossible(nextJob)
    }

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

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
