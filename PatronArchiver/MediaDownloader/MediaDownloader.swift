import Foundation
import UniformTypeIdentifiers
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

                    let destinationURL = try resolveDestinationURL(
                        for: item,
                        in: directory,
                        response: response as? HTTPURLResponse,
                        index: index
                    )

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

    nonisolated private static func resolveDestinationURL(
        for item: MediaItem,
        in directory: URL,
        response: HTTPURLResponse?,
        index: Int
    ) throws -> URL {
        let prefix = String(format: "%02d", index + 1)
        let baseURL = resolveBaseURL(for: item, in: directory, response: response, index: index)
        guard let stem = FileNameSanitizer.sanitize(baseURL.deletingPathExtension().lastPathComponent) else {
            throw FileNameSanitizer.FileNameSanitizerError.emptyFileName
        }
        var destinationURL = directory.appending(component: "\(prefix) - \(stem)")
        let pathExtension = baseURL.pathExtension
        if !pathExtension.isEmpty {
            destinationURL.appendPathExtension(pathExtension)
        }
        return destinationURL
    }

    nonisolated private static func resolveBaseURL(
        for item: MediaItem,
        in directory: URL,
        response: HTTPURLResponse?,
        index: Int
    ) -> URL {
        // 1. Use explicit filename if provided
        if let filename = item.filename, !filename.isEmpty {
            return directory.appending(component: filename)
        }

        // 2. Try Content-Disposition header
        if let disposition = response?.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=") {
            var filename = String(disposition[range.upperBound...])
            filename = filename.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if let semicolonIndex = filename.firstIndex(of: ";") {
                filename = String(filename[..<semicolonIndex])
            }
            if !filename.isEmpty {
                return directory.appending(component: filename)
            }
        }

        // 3. Fall back to URL last path component
        let lastComponent = item.url.lastPathComponent
        if !lastComponent.isEmpty && lastComponent != "/" {
            return directory.appending(component: lastComponent)
        }

        // 4. Generate indexed filename, using UTType for extension when possible
        var fileURL = directory.appending(component: "\(item.type)_\(String(format: "%03d", index + 1))")
        if let mimeType = response?.mimeType,
           let utType = UTType(mimeType: mimeType),
           let ext = utType.preferredFilenameExtension {
            fileURL.appendPathExtension(ext)
        }
        return fileURL
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
