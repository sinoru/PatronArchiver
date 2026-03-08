import Testing
@testable import PatronArchiverKit

struct FileNameSanitizerTests {
    @Test func sanitizeReplacesSlash() {
        let result = FileNameSanitizer.sanitize("hello/world")
        #expect(result == "hello_world")
    }

    @Test func sanitizeReplacesColon() {
        let result = FileNameSanitizer.sanitize("2026-03-04 15:30")
        #expect(result == "2026-03-04 15\\30")
    }

    @Test func sanitizeReplacesSlashAndColon() {
        let result = FileNameSanitizer.sanitize("path/to:file")
        #expect(result == "path_to\\file")
    }

    @Test func sanitizeEmptyStringReturnsNil() {
        #expect(FileNameSanitizer.sanitize("") == nil)
    }

    @Test func sanitizeWhitespaceOnlyReturnsNil() {
        #expect(FileNameSanitizer.sanitize("   ") == nil)
    }

    @Test func sanitizeTruncatesLongNames() throws {
        let longName = String(repeating: "a", count: 300)
        let result = try #require(FileNameSanitizer.sanitize(longName))
        #expect(result.utf8.count <= 255)
    }

    @Test func sanitizeTruncatesLongStemPreservingExtension() throws {
        let longName = String(repeating: "a", count: 300) + ".mhtml"
        let result = try #require(FileNameSanitizer.sanitize(longName))
        #expect(result.utf8.count <= 255)
        #expect(result.hasSuffix(".mhtml"))
    }

    @Test func sanitizeTrimsWhitespace() {
        let result = FileNameSanitizer.sanitize("  hello  ")
        #expect(result == "hello")
    }

    @Test func sanitizePreservesNormalCharacters() {
        let result = FileNameSanitizer.sanitize("my_file-name (1).txt")
        #expect(result == "my_file-name (1).txt")
    }

    @Test func sanitizePathJoinsComponents() throws {
        let result = try FileNameSanitizer.sanitizePath(["author:name", "post/title"])
        #expect(result == "author\\name/post_title")
    }
}
