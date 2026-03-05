import Foundation

enum FileNameSanitizer {
    nonisolated private static let maxBytes = 255

    nonisolated static func sanitize(_ name: String) -> String? {
        var sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "\\")
            .replacingOccurrences(of: "\0", with: "")

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            return nil
        }

        // Split into stem and extension at the last "."
        let stem: String
        let ext: String
        if let dotIndex = sanitized.lastIndex(of: "."), dotIndex != sanitized.startIndex {
            stem = String(sanitized[..<dotIndex])
            ext = String(sanitized[dotIndex...]) // includes the "."
        } else {
            stem = sanitized
            ext = ""
        }

        let extBytes = ext.utf8.count
        let maxStemBytes = maxBytes - extBytes

        if stem.utf8.count > maxStemBytes {
            var truncated = stem
            while truncated.utf8.count > maxStemBytes {
                truncated.removeLast()
            }
            truncated = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
            if truncated.isEmpty { return nil }
            return truncated + ext
        }

        return sanitized
    }

    nonisolated static func sanitizePath(_ components: [String]) throws -> String {
        try components.map {
            guard let sanitized = sanitize($0) else {
                throw FileNameSanitizerError.emptyFileName
            }
            return sanitized
        }.joined(separator: "/")
    }

    enum FileNameSanitizerError: LocalizedError {
        case emptyFileName

        var errorDescription: String? {
            switch self {
            case .emptyFileName:
                "File name is empty after sanitization."
            }
        }
    }
}
