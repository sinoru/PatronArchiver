import Foundation

extension URL {
    func withSecurityScopedAccess<T, E: Error>(_ work: () throws(E) -> T) throws(E) -> T {
        let didStart = startAccessingSecurityScopedResource()
        defer {
            if didStart { stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    func withSecurityScopedAccess<T, E: Error>(_ work: () async throws(E) -> T) async throws(E) -> T {
        let didStart = startAccessingSecurityScopedResource()
        defer {
            if didStart { stopAccessingSecurityScopedResource() }
        }
        return try await work()
    }
}
