import Foundation
import OSLog

enum StorageManager {
    private static let logger = Logger(subsystem: "com.sinoru.PatronArchiver", category: "StorageManager")

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    nonisolated static func save(
        metadata: PostMetadata,
        pageTitle: String,
        pdfData: Data?,
        mhtmlData: Data?,
        downloadedMedia: [MediaDownloader.DownloadedMedia],
        to baseDirectory: URL
    ) throws {
        let postFolder = makePostFolderURL(metadata: metadata, baseDirectory: baseDirectory)
        logger.info("Post folder: \(postFolder.path(), privacy: .private)")

        try FileManager.default.createDirectory(at: postFolder, withIntermediateDirectories: true)
        logger.debug("Directory created")

        // Save PDF
        let sanitizedPageTitle = FileNameSanitizer.sanitize(pageTitle)
        if let pdfData {
            let pdfURL = postFolder.appendingPathComponent("\(sanitizedPageTitle).pdf")
            try pdfData.write(to: pdfURL)
            try? XattrHelper.setWhereFroms(
                metadata.redirectChain.isEmpty ? [metadata.originalURL] : metadata.redirectChain,
                on: pdfURL.path
            )
        }

        // Save MHTML
        if let mhtmlData {
            let mhtmlURL = postFolder.appendingPathComponent("\(sanitizedPageTitle).mhtml")
            try mhtmlData.write(to: mhtmlURL)
            try? XattrHelper.setWhereFroms(
                metadata.redirectChain.isEmpty ? [metadata.originalURL] : metadata.redirectChain,
                on: mhtmlURL.path
            )
        }

        // Move downloaded media into post folder
        let fm = FileManager.default
        for media in downloadedMedia {
            let destURL = postFolder.appendingPathComponent(media.localURL.lastPathComponent)
            let sourceExists = fm.fileExists(atPath: media.localURL.path(percentEncoded: false))
            let destDirExists = fm.fileExists(atPath: postFolder.path(percentEncoded: false))
            logger.debug("Moving \(media.localURL.lastPathComponent) — source exists: \(sourceExists), dest dir exists: \(destDirExists)")
            logger.debug("  from: \(media.localURL.path(percentEncoded: false), privacy: .private)")
            logger.debug("  to:   \(destURL.path(percentEncoded: false), privacy: .private)")
            if fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: media.localURL, to: destURL)
            try? XattrHelper.setWhereFroms([media.item.url], on: destURL.path)
        }

        // Set xattr on post folder
        try? XattrHelper.setWhereFroms(
            metadata.redirectChain.isEmpty ? [metadata.originalURL] : metadata.redirectChain,
            on: postFolder.path
        )
        if !metadata.tags.isEmpty {
            try? XattrHelper.setUserTags(metadata.tags, on: postFolder.path)
        }
    }

    nonisolated static func makePostFolderURL(metadata: PostMetadata, baseDirectory: URL) -> URL {
        let authorFolder = FileNameSanitizer.sanitize(metadata.authorName)
        let dateString = dateFormatter.string(from: metadata.displayDate)
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
