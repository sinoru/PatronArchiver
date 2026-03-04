import Foundation

enum FileNameSanitizer {
    private static let maxLength = 255

    nonisolated static func sanitize(_ name: String) -> String {
        var sanitized = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            sanitized = "untitled"
        }

        if sanitized.utf8.count > maxLength {
            while sanitized.utf8.count > maxLength - 10 {
                sanitized.removeLast()
            }
        }

        return sanitized
    }

    nonisolated static func sanitizePath(_ components: [String]) -> String {
        components.map { sanitize($0) }.joined(separator: "/")
    }
}
