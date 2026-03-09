import Foundation
import Testing
@testable import PatronArchiverKit

struct PatronServiceManagerTests {
    @Test func matchesPatreonURL() throws {
        let url = URL(string: "https://www.patreon.com/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == PatreonProvider.self)
    }

    @Test func matchesPatreonURLWithoutWWW() throws {
        let url = URL(string: "https://patreon.com/posts/some-title-12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == PatreonProvider.self)
    }

    @Test func matchesPixivFanboxURL() throws {
        let url = URL(string: "https://creator.fanbox.cc/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == PixivFanboxProvider.self)
    }

    @Test func matchesPixivFanboxWWWURL() throws {
        let url = URL(string: "https://www.fanbox.cc/@creator/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == PixivFanboxProvider.self)
    }

    @Test func matchesSubscribeStarAdultURL() throws {
        let url = URL(string: "https://subscribestar.adult/posts/2332276")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == SubscribeStarAdultProvider.self)
    }

    @Test func returnsNilForUnknownSite() {
        let url = URL(string: "https://example.com/page")!
        let provider = PatronServiceManager.shared.provider(for: url)
        #expect(provider == nil)
    }

    @Test func allProviderTypesReturnsAllThree() {
        let types = PatronServiceManager.allProviderTypes
        #expect(types.count == 3)
    }
}
