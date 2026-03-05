import Foundation
import OSLog

enum StorageManager {
    nonisolated private static let logger = Logger(subsystem: "com.sinoru.PatronArchiver", category: "StorageManager")

    nonisolated private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    struct PreparedSave {
        let stagingDirectory: URL
        let finalDirectory: URL
    }

    // MARK: - Phase 1: Prepare all files in staging directory

    nonisolated static func prepareSave(
        metadata: PostMetadata,
        pageTitle: String,
        pdfData: Data?,
        mhtmlData: Data?,
        downloadedMedia: [MediaDownloader.DownloadedMedia],
        stagingDirectory: URL,
        baseDirectory: URL
    ) throws -> PreparedSave {
        let finalDirectory = makePostFolderURL(metadata: metadata, baseDirectory: baseDirectory)
        let sanitizedPageTitle = FileNameSanitizer.sanitize(pageTitle)
        let whereFroms = metadata.redirectChain.isEmpty ? [metadata.originalURL] : metadata.redirectChain

        logger.info("Preparing save in staging: \(stagingDirectory.path(), privacy: .private)")
        logger.info("Final directory: \(finalDirectory.path(), privacy: .private)")

        // Write PDF to staging
        if let pdfData {
            let pdfURL = stagingDirectory.appendingPathComponent("\(sanitizedPageTitle).pdf")
            try pdfData.write(to: pdfURL, options: .atomic)
            try? XattrHelper.setWhereFroms(whereFroms, on: pdfURL.path)
        }

        // Write MHTML to staging
        if let mhtmlData {
            let mhtmlURL = stagingDirectory.appendingPathComponent("\(sanitizedPageTitle).mhtml")
            try mhtmlData.write(to: mhtmlURL, options: .atomic)
            try? XattrHelper.setWhereFroms(whereFroms, on: mhtmlURL.path)
        }

        // Set xattr on media files (already in staging from MediaDownloader)
        for media in downloadedMedia {
            try? XattrHelper.setWhereFroms([media.item.url], on: media.localURL.path)
        }

        // Set xattr on staging folder
        try? XattrHelper.setWhereFroms(whereFroms, on: stagingDirectory.path)
        if !metadata.tags.isEmpty {
            try? XattrHelper.setUserTags(metadata.tags, on: stagingDirectory.path)
        }

        return PreparedSave(stagingDirectory: stagingDirectory, finalDirectory: finalDirectory)
    }

    // MARK: - Phase 2: Move staging to final location

    nonisolated static func commitSave(_ preparedSave: PreparedSave, overwrite: Bool) throws {
        let fm = FileManager.default
        let finalDirectory = preparedSave.finalDirectory

        logger.info("Committing save to: \(finalDirectory.path(), privacy: .private), overwrite: \(overwrite)")

        if overwrite, fm.fileExists(atPath: finalDirectory.path(percentEncoded: false)) {
            try fm.removeItem(at: finalDirectory)
            logger.debug("Removed existing folder")
        }

        // Ensure parent (author) directory exists
        let parentDirectory = finalDirectory.deletingLastPathComponent()
        try fm.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        try fm.moveItem(at: preparedSave.stagingDirectory, to: finalDirectory)
        logger.info("Save committed successfully")
    }

    // MARK: - Check if post folder already exists

    nonisolated static func postFolderExists(metadata: PostMetadata, baseDirectory: URL) -> Bool {
        let postFolder = makePostFolderURL(metadata: metadata, baseDirectory: baseDirectory)
        return FileManager.default.fileExists(atPath: postFolder.path(percentEncoded: false))
    }

    // MARK: - Discard staging on cancel

    nonisolated static func discardPreparedSave(_ preparedSave: PreparedSave) {
        do {
            try FileManager.default.removeItem(at: preparedSave.stagingDirectory)
            logger.debug("Discarded staging directory: \(preparedSave.stagingDirectory.path(), privacy: .private)")
        } catch {
            logger.warning("Failed to discard staging directory: \(error.localizedDescription)")
        }
    }

    nonisolated static func makePostFolderURL(metadata: PostMetadata, baseDirectory: URL) -> URL {
        let authorFolder = FileNameSanitizer.sanitize(metadata.authorName)
        let dateString = dateFormatter.string(from: metadata.modifiedAt ?? metadata.createdAt)
        let postFolder = FileNameSanitizer.sanitize(
            "\(metadata.postID) - \(metadata.title) (\(dateString))"
        )
        return baseDirectory
            .appendingPathComponent(authorFolder)
            .appendingPathComponent(postFolder)
    }

    nonisolated static func temporaryDownloadDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatronArchiver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}
