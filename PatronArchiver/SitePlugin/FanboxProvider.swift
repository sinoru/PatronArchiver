import Foundation
import WebKit

struct FanboxProvider: PatronServiceProvider {
    static let matchPatterns = [
        "https://*.fanbox.cc/posts/*",
        "https://www.fanbox.cc/@*/posts/*",
    ]
    static let loginURL = URL(string: "https://www.fanbox.cc/login")!
    static let accountCheckURL = URL(string: "https://www.fanbox.cc/user/settings")!
    static let siteIdentifier = "fanbox"

    static func parseAccountInfo(from data: Data) -> AccountInfo? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // Parse user name from #metadata content attribute JSON
        // e.g. <meta id="metadata" name="metadata" content='{"context":{"user":{"name":"..."}}}'>
        if let contentRange = html.range(of: #"<meta[^>]+id="metadata"[^>]+content='([^']+)'"#, options: .regularExpression),
           let jsonStart = html[contentRange].range(of: "content='") {
            let jsonFragment = html[contentRange][jsonStart.upperBound...]
                .prefix(while: { $0 != "'" })
            if let jsonData = String(jsonFragment).data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let context = root["context"] as? [String: Any],
               let user = context["user"] as? [String: Any],
               let name = user["name"] as? String,
               !name.isEmpty {
                return AccountInfo(displayName: name)
            }
        }

        return nil
    }

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.cookie.includes('FANBOXSESSID') || document.querySelector('[href*=\"/creators/find\"]') !== null",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Fanbox article type posts may have expandable sections
        _ = try? await evaluateJavaScript("""
            (() => {
                // Click any "read more" buttons
                document.querySelectorAll('button').forEach(btn => {
                    if (btn.textContent.includes('もっと見る') || btn.textContent.includes('Read more')) {
                        btn.click();
                    }
                });
            })()
        """, in: webView)
        try? await Task.sleep(for: .milliseconds(500))
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        let script = """
        (() => {
            const media = [];

            // Article type: links with target=_blank (download links) — full size originals
            document.querySelectorAll('article a[target="_blank"]').forEach(a => {
                const href = a.href;
                if (href && (href.includes('downloads.fanbox.cc') || href.includes('fanbox.pixiv.net'))) {
                    media.push({ url: href, type: 'image', filename: null });
                }
            });

            // Image posts: img tags inside article, NOT inside a download link
            document.querySelectorAll('article img').forEach(img => {
                if (img.src && !img.closest('a[target="_blank"]') && !media.some(m => m.url === img.src)) {
                    media.push({ url: img.src, type: 'image', filename: null });
                }
            });

            // File posts: download links
            document.querySelectorAll('a[href*="downloads.fanbox.cc"]').forEach(a => {
                if (!media.some(m => m.url === a.href)) {
                    const nameEl = a.closest('[class*="File"]')?.querySelector('[class*="name"], [class*="Name"]');
                    media.push({
                        url: a.href,
                        type: 'archive',
                        filename: nameEl?.textContent?.trim() || null
                    });
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

            // Post ID from URL
            const pathMatch = location.pathname.match(/posts\\/(\\d+)/);
            meta.postID = pathMatch ? pathMatch[1] : '';

            // Title — PostTitle class (not generic h1 which matches author name first)
            const titleEl = document.querySelector('[class*="PostTitle"]');
            meta.title = titleEl?.textContent?.trim() || document.title;

            // Author — UserNameText in creator header (not CreatorName which matches footer recommendations)
            const authorEl = document.querySelector('[class*="UserNameText"]');
            if (authorEl) {
                meta.authorName = authorEl.textContent.trim();
            } else {
                const hostMatch = location.hostname.match(/^([^.]+)\\.fanbox\\.cc$/);
                if (hostMatch) {
                    meta.authorName = hostMatch[1];
                }
            }

            // Date — parse from PostHeadBottom (no <time datetime> on Fanbox)
            const dateEl = document.querySelector('[class*="PostHeadBottom"]');
            if (dateEl) {
                const dateText = dateEl.textContent.split('・')[0].trim();
                // JA: 2026年3月4日 21:11 / KO: 2026년3월4일 21:11
                let m = dateText.match(/(\\d{4})[年년](\\d{1,2})[月월](\\d{1,2})[日일]\\s*(\\d{2}):(\\d{2})/);
                if (m) {
                    meta.createdAt = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]).toISOString();
                } else {
                    // EN: March 4th, 2026 21:11
                    const months = { January:0, February:1, March:2, April:3, May:4, June:5, July:6, August:7, September:8, October:9, November:10, December:11 };
                    m = dateText.match(/(\\w+)\\s+(\\d{1,2})\\w*,?\\s*(\\d{4})\\s*(\\d{2}):(\\d{2})/);
                    if (m && months[m[1]] !== undefined) {
                        meta.createdAt = new Date(+m[3], months[m[1]], +m[2], +m[4], +m[5]).toISOString();
                    } else {
                        meta.createdAt = new Date().toISOString();
                    }
                }
            } else {
                meta.createdAt = new Date().toISOString();
            }

            // Tags
            meta.tags = Array.from(document.querySelectorAll('[class*="Tag__Text"]'))
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
            throw ProviderError.metadataExtractionFailed
        }
        return metadata
    }
}
