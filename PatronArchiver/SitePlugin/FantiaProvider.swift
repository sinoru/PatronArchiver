import Foundation
import WebKit

struct FantiaProvider: PatronServiceProvider {
    static let matchPatterns = [
        "https://fantia.jp/posts/*",
    ]
    static let loginURL = URL(string: "https://fantia.jp/sessions/signin")!
    static let accountCheckURL = URL(string: "https://fantia.jp/mypage")!
    static let siteIdentifier = "fantia"

    static func parseAccountInfo(from data: Data) -> AccountInfo? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        // Look for username in mypage HTML
        if let range = html.range(of: #"class="[^"]*user-name[^"]*"[^>]*>([^<]+)<"#, options: .regularExpression) {
            let match = String(html[range])
            if let gtIndex = match.lastIndex(of: ">"),
               let ltIndex = match.lastIndex(of: "<") {
                let name = String(match[match.index(after: gtIndex)..<ltIndex])
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return AccountInfo(displayName: name) }
            }
        }
        // Fallback: parse <title>
        if let titleStart = html.range(of: "<title>"),
           let titleEnd = html.range(of: "</title>", range: titleStart.upperBound..<html.endIndex) {
            let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !title.contains("Fantia") || title.count > 10 {
                return AccountInfo(displayName: title)
            }
        }
        return nil
    }

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('.logout-link, a[href*=\"/mypage\"]') !== null",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Click "show more" on content sections
        _ = try? await evaluateJavaScript("""
            (() => {
                document.querySelectorAll('.btn, button').forEach(btn => {
                    const text = btn.textContent.trim();
                    if (text === '全て見る' || text === 'もっと見る') {
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

            // Images with data-image-url attribute
            document.querySelectorAll('[data-image-url]').forEach(el => {
                const url = el.getAttribute('data-image-url');
                if (url) media.push({ url: url, type: 'image', filename: null });
            });

            // Regular images in post content
            document.querySelectorAll('.post-content img[src], .the-post img[src]').forEach(img => {
                if (img.src && !img.src.includes('emoji') && !media.some(m => m.url === img.src)) {
                    media.push({ url: img.src, type: 'image', filename: null });
                }
            });

            // Download links
            document.querySelectorAll('a[download], a[href*="/download"]').forEach(a => {
                if (a.href) {
                    media.push({
                        url: a.href,
                        type: 'archive',
                        filename: a.getAttribute('download') || a.textContent?.trim() || null
                    });
                }
            });

            // Video
            document.querySelectorAll('video source[src], video[src]').forEach(el => {
                if (el.src) media.push({ url: el.src, type: 'video', filename: null });
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

            // Title
            const titleEl = document.querySelector('.post-title, h1.the-post-title, h1');
            meta.title = titleEl?.textContent?.trim() || document.title;

            // Author
            const authorEl = document.querySelector('.fanclub-name a, .the-fanclub-name');
            meta.authorName = authorEl?.textContent?.trim() || '';

            // Date
            const dateEl = document.querySelector('.post-date, time[datetime], .the-post-date');
            if (dateEl?.getAttribute('datetime')) {
                meta.createdAt = dateEl.getAttribute('datetime');
            } else if (dateEl) {
                meta.createdAt = dateEl.textContent.trim();
            } else {
                meta.createdAt = new Date().toISOString();
            }

            // Tags
            meta.tags = Array.from(document.querySelectorAll('.post-tag a, a[href*="/posts?tag="]'))
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
