import Foundation
import WebKit

enum MediaDownloader {
    struct DownloadedMedia: Sendable {
        let item: MediaItem
        let localURL: URL
        let downloadRedirects: [URL]
    }

    @concurrent
    static func download(
        items: [MediaItem],
        to directory: URL,
        dataStore: WKWebsiteDataStore
    ) async throws -> [DownloadedMedia] {
        try await withThrowingTaskGroup(of: DownloadedMedia?.self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let request = await CookieHelper.configuredRequest(for: item.url, dataStore: dataStore)
                    let redirectCollector = RedirectCollector()
                    let (tempURL, response) = try await URLSession.shared.download(
                        for: request,
                        delegate: redirectCollector
                    )

                    let baseFilename = resolveFilename(
                        for: item,
                        response: response as? HTTPURLResponse,
                        index: index
                    )
                    let filename = addIndexPrefix(baseFilename, index: index)
                    let sanitized = FileNameSanitizer.sanitize(filename)
                    let destinationURL = directory.appendingPathComponent(sanitized)

                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                    return DownloadedMedia(
                        item: item,
                        localURL: destinationURL,
                        downloadRedirects: redirectCollector.redirectedURLs
                    )
                }
            }

            var results: [DownloadedMedia] = []
            for try await media in group {
                if let media { results.append(media) }
            }
            return results
        }
    }

    nonisolated private static func resolveFilename(
        for item: MediaItem,
        response: HTTPURLResponse?,
        index: Int
    ) -> String {
        // 1. Use explicit filename if provided
        if let filename = item.filename, !filename.isEmpty {
            return filename
        }

        // 2. Try Content-Disposition header
        if let disposition = response?.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=") {
            var filename = String(disposition[range.upperBound...])
            filename = filename.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if let semicolonIndex = filename.firstIndex(of: ";") {
                filename = String(filename[..<semicolonIndex])
            }
            if !filename.isEmpty { return filename }
        }

        // 3. Fall back to URL last path component
        let lastComponent = item.url.lastPathComponent
        if !lastComponent.isEmpty && lastComponent != "/" {
            return lastComponent
        }

        // 4. Generate indexed filename
        let ext = switch item.type {
        case .image: "jpg"
        case .video: "mp4"
        case .audio: "mp3"
        case .archive: "zip"
        case .game: "zip"
        case .other: "bin"
        }
        return "\(item.type)_\(String(format: "%03d", index + 1)).\(ext)"
    }

    nonisolated private static func addIndexPrefix(_ filename: String, index: Int) -> String {
        let prefix = String(format: "%02d", index + 1)
        return "\(prefix) - \(filename)"
    }
}

private final class RedirectCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []

    var redirectedURLs: [URL] {
        lock.withLock { _urls }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        if let url = request.url {
            lock.withLock { _urls.append(url) }
        }
        return request
    }
}
