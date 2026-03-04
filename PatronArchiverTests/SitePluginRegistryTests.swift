import Foundation
import Testing
@testable import PatronArchiver

struct SitePluginRegistryTests {
    @Test func matchesPatreonURL() {
        let url = URL(string: "https://www.patreon.com/posts/12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == PatreonPlugin.self)
    }

    @Test func matchesPatreonURLWithoutWWW() {
        let url = URL(string: "https://patreon.com/posts/some-title-12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == PatreonPlugin.self)
    }

    @Test func matchesFanboxURL() {
        let url = URL(string: "https://creator.fanbox.cc/@creator/posts/12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == FanboxPlugin.self)
    }

    @Test func matchesFanboxWWWURL() {
        let url = URL(string: "https://www.fanbox.cc/@creator/posts/12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == FanboxPlugin.self)
    }

    @Test func matchesFantiaURL() {
        let url = URL(string: "https://fantia.jp/posts/12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == FantiaPlugin.self)
    }

    @Test func matchesItchURL() {
        let url = URL(string: "https://creator.itch.io/game-name")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == ItchPlugin.self)
    }

    @Test func matchesSubscribeStarURL() {
        let url = URL(string: "https://subscribestar.adult/posts/12345")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin != nil)
        #expect(type(of: plugin!) == SubscribeStarPlugin.self)
    }

    @Test func returnsNilForUnknownSite() {
        let url = URL(string: "https://example.com/page")!
        let plugin = SitePluginRegistry.shared.plugin(for: url)
        #expect(plugin == nil)
    }

    @Test func allPluginTypesReturnsAllFive() {
        let types = SitePluginRegistry.shared.allPluginTypes
        #expect(types.count == 5)
    }
}
