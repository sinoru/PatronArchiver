import Foundation
import WebKit

struct SubscribeStarPlugin: SitePlugin {
    static let matchPatterns = [
        "https://subscribestar.adult/posts/*",
        "https://www.subscribestar.adult/posts/*",
    ]
    static let loginURL = URL(string: "https://subscribestar.adult/login")!
    static let siteIdentifier = "subscribestar"

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('.user-menu, .profile-menu, a[href*=\"/profile\"]') !== null",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Expand any collapsed content
        _ = try? await evaluateJavaScript("""
            (() => {
                document.querySelectorAll('.show-more-btn, [data-action="show-more"]').forEach(btn => {
                    btn.click();
                });
            })()
        """, in: webView)
        try? await Task.sleep(for: .milliseconds(500))
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        let script = """
        (() => {
            const media = [];

            // data-gallery JSON attribute (used for image galleries)
            document.querySelectorAll('[data-gallery]').forEach(el => {
                try {
                    const gallery = JSON.parse(el.getAttribute('data-gallery'));
                    if (Array.isArray(gallery)) {
                        gallery.forEach(item => {
                            const url = item.url || item.src || item.original;
                            if (url) media.push({ url: url, type: 'image', filename: null });
                        });
                    }
                } catch {}
            });

            // Post content images
            document.querySelectorAll('.post-content img[src], .trix-content img[src]').forEach(img => {
                if (img.src && !media.some(m => m.url === img.src)) {
                    media.push({ url: img.src, type: 'image', filename: null });
                }
            });

            // Attachment download links
            document.querySelectorAll('a.attachment-link, a[data-file-download]').forEach(a => {
                if (a.href) {
                    media.push({
                        url: a.href,
                        type: 'archive',
                        filename: a.textContent?.trim() || null
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
            const titleEl = document.querySelector('.post-title, h1, .post-header h2');
            meta.title = titleEl?.textContent?.trim() || document.title;

            // Author
            const authorEl = document.querySelector('.post-user .post-user-name, .profile-name, a[href*="/profile"]');
            meta.authorName = authorEl?.textContent?.trim() || '';

            // Date
            const dateEl = document.querySelector('.post-date time, time[datetime], .post-date');
            if (dateEl?.getAttribute('datetime')) {
                meta.createdAt = dateEl.getAttribute('datetime');
            } else if (dateEl) {
                meta.createdAt = dateEl.textContent.trim();
            } else {
                meta.createdAt = new Date().toISOString();
            }

            // Tags
            meta.tags = Array.from(document.querySelectorAll('.post-tags a, a[href*="/tag/"]'))
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
