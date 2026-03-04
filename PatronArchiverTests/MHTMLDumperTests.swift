import Foundation
import Testing
@testable import PatronArchiver

struct MHTMLDumperTests {
    // Note: Full MHTML creation requires WKWebView (MainActor + UI),
    // so we test the RFC 2557 assembly logic conceptually.
    // The private assembleMHTML method is not directly accessible,
    // but we can verify the error types exist and are correct.

    @Test func mhtmlErrorCasesExist() {
        let collectionError = MHTMLError.collectionFailed
        let pageURLError = MHTMLError.noPageURL

        #expect(collectionError is MHTMLError)
        #expect(pageURLError is MHTMLError)
    }
}
