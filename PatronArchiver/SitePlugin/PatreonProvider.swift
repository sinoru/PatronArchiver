import Foundation
import WebKit

struct PatreonProvider: PatronServiceProvider {
    static let matchPatterns = [
        "https://www.patreon.com/posts/*",
        "https://patreon.com/posts/*",
    ]
    static let loginURL = URL(string: "https://www.patreon.com/login")!
    static let accountCheckURL = URL(string: "https://www.patreon.com/settings/profile")!
    static let siteIdentifier = "patreon"

    static func parseAccountInfo(from data: Data) -> AccountInfo? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        // Try __NEXT_DATA__ JSON for user info
        if let startRange = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
           let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex),
           let jsonData = String(html[startRange.upperBound..<endRange.lowerBound]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let props = json["props"] as? [String: Any],
           let pageProps = props["pageProps"] as? [String: Any],
           let bootstrap = (pageProps["bootstrapEnvelope"] as? [String: Any])?["bootstrap"] as? [String: Any],
           let userData = bootstrap["currentUser"] as? [String: Any],
           let attributes = userData["data"] as? [String: Any],
           let name = (attributes["attributes"] as? [String: Any])?["full_name"] as? String {
            return AccountInfo(displayName: name)
        }
        // Fallback: parse <title> — typically "Settings | Name | Patreon"
        if let titleStart = html.range(of: "<title>"),
           let titleEnd = html.range(of: "</title>", range: titleStart.upperBound..<html.endIndex) {
            let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
            let parts = title.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, !parts[1].isEmpty, parts[1] != "Patreon" {
                return AccountInfo(displayName: parts[1])
            }
        }
        return nil
    }

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('[data-tag=\"logged-in-user\"]') !== null || document.cookie.includes('session_id')",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Expand truncated post content if present
        _ = try? await evaluateJavaScript("""
            (() => {
                const expandButtons = document.querySelectorAll('[data-tag="expand-post"]');
                expandButtons.forEach(btn => btn.click());
            })()
        """, in: webView)
        try? await Task.sleep(for: .milliseconds(500))
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        // Extract from __NEXT_DATA__ JSON + DOM images
        let script = """
        (() => {
            const media = [];

            // Try __NEXT_DATA__ for structured data
            const nextData = document.getElementById('__NEXT_DATA__');
            if (nextData) {
                try {
                    const data = JSON.parse(nextData.textContent);
                    const post = data?.props?.pageProps?.bootstrapEnvelope?.bootstrap?.post;
                    if (post?.included) {
                        for (const item of post.included) {
                            if (item.type === 'media' && item.attributes) {
                                const attrs = item.attributes;
                                const url = attrs.download_url || attrs.image_urls?.original || attrs.image_urls?.url;
                                if (url) {
                                    media.push({
                                        url: url,
                                        type: attrs.media_type === 'video' ? 'video' : 'image',
                                        filename: attrs.file_name || null
                                    });
                                }
                            }
                            if (item.type === 'attachment' && item.attributes?.url) {
                                media.push({
                                    url: item.attributes.url,
                                    type: 'archive',
                                    filename: item.attributes.name || null
                                });
                            }
                        }
                    }
                } catch {}
            }

            // Also scan DOM for images not in structured data
            const postContent = document.querySelector('[data-tag="post-content"]');
            if (postContent) {
                postContent.querySelectorAll('img[src]').forEach(img => {
                    const src = img.src;
                    if (src && !media.some(m => m.url === src) && !src.includes('emoji')) {
                        media.push({ url: src, type: 'image', filename: null });
                    }
                });
            }

            // Download links
            document.querySelectorAll('a[data-tag="post-download-link"]').forEach(a => {
                if (a.href) {
                    media.push({ url: a.href, type: 'archive', filename: a.textContent?.trim() || null });
                }
            });

            return JSON.stringify(media);
        })()
        """
        guard let jsonString = try await evaluateJavaScript(script, in: webView) as? String else {
            return []
        }
        let referrer = webView.url
        return parseMediaJSON(jsonString, referrerURL: referrer)
    }

    func extractMetadata(in webView: WKWebView) async throws -> PostMetadata {
        let script = """
        (() => {
            const meta = {};

            // Try __NEXT_DATA__ first
            const nextData = document.getElementById('__NEXT_DATA__');
            if (nextData) {
                try {
                    const data = JSON.parse(nextData.textContent);
                    const post = data?.props?.pageProps?.bootstrapEnvelope?.bootstrap?.post;
                    if (post?.data?.attributes) {
                        const attrs = post.data.attributes;
                        meta.postID = post.data.id || '';
                        meta.title = attrs.title || '';
                        meta.createdAt = attrs.published_at || attrs.created_at || '';
                        meta.modifiedAt = attrs.edited_at || null;
                        if (attrs.tags) {
                            meta.tags = attrs.tags.map(t => typeof t === 'string' ? t : t.value || '');
                        }
                    }
                    if (post?.included) {
                        for (const item of post.included) {
                            if (item.type === 'user' || item.type === 'campaign') {
                                if (item.attributes?.name || item.attributes?.full_name) {
                                    meta.authorName = item.attributes.full_name || item.attributes.name;
                                    break;
                                }
                            }
                        }
                    }
                } catch {}
            }

            // Fallback: DOM scraping
            if (!meta.title) {
                const titleEl = document.querySelector('h1, [data-tag="post-title"]');
                meta.title = titleEl?.textContent?.trim() || document.title;
            }
            if (!meta.authorName) {
                const authorEl = document.querySelector('[data-tag="creator-name"], a[href*="/c/"]');
                meta.authorName = authorEl?.textContent?.trim() || '';
            }
            if (!meta.postID) {
                const match = location.pathname.match(/posts\\/(\\d+)/);
                meta.postID = match ? match[1] : '';
            }
            meta.tags = meta.tags || [];
            if (!meta.createdAt) meta.createdAt = new Date().toISOString();

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

enum ProviderError: LocalizedError {
    case metadataExtractionFailed
    case mediaExtractionFailed

    var errorDescription: String? {
        switch self {
        case .metadataExtractionFailed: "Failed to extract metadata."
        case .mediaExtractionFailed: "Failed to extract media."
        }
    }
}
