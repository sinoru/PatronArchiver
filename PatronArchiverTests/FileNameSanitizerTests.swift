import Testing
@testable import PatronArchiver

struct FileNameSanitizerTests {
    @Test func sanitizeReplacesSlash() {
        let result = FileNameSanitizer.sanitize("hello/world")
        #expect(result == "hello_world")
    }

    @Test func sanitizeReplacesColon() {
        let result = FileNameSanitizer.sanitize("2026-03-04 15:30")
        #expect(result == "2026-03-04 15_30")
    }

    @Test func sanitizeReplacesSlashAndColon() {
        let result = FileNameSanitizer.sanitize("path/to:file")
        #expect(result == "path_to_file")
    }

    @Test func sanitizeEmptyStringBecomesUntitled() {
        let result = FileNameSanitizer.sanitize("")
        #expect(result == "untitled")
    }

    @Test func sanitizeWhitespaceOnlyBecomesUntitled() {
        let result = FileNameSanitizer.sanitize("   ")
        #expect(result == "untitled")
    }

    @Test func sanitizeTruncatesLongNames() {
        let longName = String(repeating: "a", count: 300)
        let result = FileNameSanitizer.sanitize(longName)
        #expect(result.utf8.count <= 255)
    }

    @Test func sanitizeTrimsWhitespace() {
        let result = FileNameSanitizer.sanitize("  hello  ")
        #expect(result == "hello")
    }

    @Test func sanitizePreservesNormalCharacters() {
        let result = FileNameSanitizer.sanitize("my_file-name (1).txt")
        #expect(result == "my_file-name (1).txt")
    }

    @Test func sanitizePathJoinsComponents() {
        let result = FileNameSanitizer.sanitizePath(["author:name", "post/title"])
        #expect(result == "author_name/post_title")
    }
}
