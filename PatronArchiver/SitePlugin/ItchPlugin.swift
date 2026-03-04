import Foundation
import WebKit

struct ItchPlugin: SitePlugin {
    static let matchPatterns = [
        "https://*.itch.io/*",
    ]
    static let loginURL = URL(string: "https://itch.io/login")!
    static let siteIdentifier = "itch"

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('.user_panel, .logged_in') !== null || document.cookie.includes('itchio_token')",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // itch.io pages are generally static, no special preload needed
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        let script = """
        (() => {
            const media = [];

            // Download links (game files)
            document.querySelectorAll('.upload a.button[href*="/file/"], a[href*="/download"]').forEach(a => {
                if (a.href) {
                    const nameEl = a.closest('.upload')?.querySelector('.name, .upload_name');
                    media.push({
                        url: a.href,
                        type: 'game',
                        filename: nameEl?.textContent?.trim() || null
                    });
                }
            });

            // Description images
            const description = document.querySelector('.formatted_description, .page_widget');
            if (description) {
                description.querySelectorAll('img[src]').forEach(img => {
                    if (img.src) {
                        media.push({ url: img.src, type: 'image', filename: null });
                    }
                });
            }

            // Screenshots / cover image
            document.querySelectorAll('.screenshot_list img[src], .header img[src]').forEach(img => {
                if (img.src && !media.some(m => m.url === img.src)) {
                    media.push({ url: img.src, type: 'image', filename: null });
                }
            });

            return JSON.stringify(media);
        })()
        """
        guard let jsonString = try await evaluateJavaScript(script, in: webView) as? String else {
            return []
        }
        return parseMediaJSON(jsonString, referrerURL: webView.url)
    }

    func extractMetadata(in webView: WKWebView) async throws -> PostMetadata {
        let script = """
        (() => {
            const meta = {};

            // Extract from URL: creator.itch.io/game-name
            const hostMatch = location.hostname.match(/^([^.]+)\\.itch\\.io$/);
            meta.authorName = hostMatch ? hostMatch[1] : '';
            meta.postID = location.pathname.replace(/^\\//, '').replace(/\\/$/, '') || 'index';

            // Title
            const titleEl = document.querySelector('h1.game_title, .game_title, h1');
            meta.title = titleEl?.textContent?.trim() || document.title;

            // Date: look for published date
            const dateEl = document.querySelector('.publish_date, time[datetime], .date_format');
            if (dateEl?.getAttribute('datetime')) {
                meta.createdAt = dateEl.getAttribute('datetime');
            } else {
                meta.createdAt = new Date().toISOString();
            }

            // Tags
            meta.tags = Array.from(document.querySelectorAll('.game_tags a, a[href*="/tag/"]'))
                .map(el => el.textContent.trim())
                .filter(t => t.length > 0);

            return JSON.stringify(meta);
        })()
        """
        guard let jsonString = try await evaluateJavaScript(script, in: webView) as? String,
              let metadata = parseMetadataJSON(
                  jsonString,
                  siteIdentifier: Self.siteIdentifier,
                  originalURL: webView.url ?? Self.loginURL,
                  redirectChain: []
              )
        else {
            throw PluginError.metadataExtractionFailed
        }
        return metadata
    }
}
