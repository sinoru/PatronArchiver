import Foundation
import Testing
@testable import PatronArchiver

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

    @Test func matchesFanboxURL() throws {
        let url = URL(string: "https://creator.fanbox.cc/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == FanboxProvider.self)
    }

    @Test func matchesFanboxWWWURL() throws {
        let url = URL(string: "https://www.fanbox.cc/@creator/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == FanboxProvider.self)
    }

    @Test func matchesFantiaURL() throws {
        let url = URL(string: "https://fantia.jp/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == FantiaProvider.self)
    }

    @Test func matchesItchURL() throws {
        let url = URL(string: "https://creator.itch.io/game-name")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == ItchProvider.self)
    }

    @Test func matchesSubscribeStarURL() throws {
        let url = URL(string: "https://subscribestar.adult/posts/12345")!
        let provider = try #require(PatronServiceManager.shared.provider(for: url))
        #expect(type(of: provider) == SubscribeStarProvider.self)
    }

    @Test func returnsNilForUnknownSite() {
        let url = URL(string: "https://example.com/page")!
        let provider = PatronServiceManager.shared.provider(for: url)
        #expect(provider == nil)
    }

    @Test func allProviderTypesReturnsAllFive() {
        let types = PatronServiceManager.shared.allProviderTypes
        #expect(types.count == 5)
    }
}
