import Foundation
import WebKit

struct PatreonProvider: PatronServiceProvider {
    static let matchPatterns: [any RegexComponent] = [
        /https:\/\/(www\.)?patreon\.com\/posts\/.+/,
    ]
    static let loginURL = URL(string: "https://www.patreon.com/login")!
    static let accountCheckURL = URL(string: "https://www.patreon.com/settings/basics")!
    static let siteIdentifier = "Patreon"

    static func parseAccountInfo(from data: Data) -> AccountInfo? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        // Try __NEXT_DATA__ JSON for user info
        let nextDataTag = #"<script id="__NEXT_DATA__" type="application/json">"#
        if let startRange = html.range(of: nextDataTag),
           let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex),
           let jsonData = String(
               html[startRange.upperBound..<endRange.lowerBound]
           ).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let props = json["props"] as? [String: Any],
           let pageProps = props["pageProps"] as? [String: Any],
           let envelope = pageProps["bootstrapEnvelope"] as? [String: Any],
           let bootstrap = envelope["commonBootstrap"] as? [String: Any],
           let userData = bootstrap["currentUser"] as? [String: Any],
           let attributes = userData["data"] as? [String: Any],
           let email = (attributes["attributes"] as? [String: Any])?["email"] as? String {
            return AccountInfo(displayName: email)
        }
        // Fallback: parse <title> — typically "Settings | Name | Patreon"
        if let titleStart = html.range(of: "<title>"),
           let titleEnd = html.range(of: "</title>", range: titleStart.upperBound..<html.endIndex) {
            let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
            let parts = title.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, !parts[1].isEmpty, parts[1] != "Patreon" {
                return AccountInfo(displayName: parts[1])
            }
        }
        return nil
    }

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('[data-tag=\"account-menu-toggle-combined\"]') !== null || document.cookie.includes('session_id')",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Load all comments and replies
        for _ in 0..<UInt16.max {
            let result = try await evaluateJavaScript("""
                (() => {
                    const before = document.querySelectorAll('[data-tag="comment-row"]').length;
                    let clicked = 0;
                    document.querySelectorAll('button[data-tag="loadMoreCommentsCta"]').forEach(btn => {
                        btn.click();
                        clicked++;
                    });
                    document.querySelectorAll('button[class*="TextLink"]').forEach(btn => {
                        if (!btn.hasAttribute('data-tag') && btn.textContent.trim() === 'Load replies') {
                            btn.click();
                            clicked++;
                        }
                    });
                    return JSON.stringify({ clicked, before });
                })()
            """, in: webView) as? String

            guard let result,
                  let json = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Int],
                  let clicked = json["clicked"], clicked > 0,
                  let before = json["before"]
            else { break }

            // Wait until new comment-rows appear or timeout
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                let current = try await evaluateJavaScript(
                    "document.querySelectorAll('[data-tag=\"comment-row\"]').length",
                    in: webView
                ) as? Int ?? 0
                if current > before { break }
            }
        }
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        let script = """
        (() => {
            const media = [];

            const nextData = document.getElementById('__NEXT_DATA__');
            if (nextData) {
                try {
                    const data = JSON.parse(nextData.textContent);
                    const post = data?.props?.pageProps?.bootstrapEnvelope?.pageBootstrap?.post;
                    if (post?.data && post?.included) {
                        const mediaById = {};
                        for (const item of post.included) {
                            if (item.type === 'media' && item.attributes) mediaById[item.id] = item;
                        }
                        const urlOf = (item) => item.attributes.download_url || item.attributes.image_urls?.original || item.attributes.image_urls?.url;

                        // 1. Gallery/header images in image_order
                        const imageOrder = post.data.attributes?.post_metadata?.image_order || [];
                        const imageIds = imageOrder.length > 0
                            ? imageOrder
                            : (post.data.relationships?.images?.data || []).map(d => d.id);
                        for (const id of imageIds) {
                            const item = mediaById[id];
                            if (item) {
                                media.push({ url: urlOf(item), type: 'image', filename: item.attributes.file_name || null });
                            }
                        }

                        // 2. Inline images from content_json_string (in document order)
                        const contentJson = post.data.attributes?.content_json_string;
                        if (contentJson) {
                            const content = JSON.parse(contentJson);
                            const walk = (nodes) => {
                                for (const node of (nodes || [])) {
                                    if (node.type === 'image' && node.attrs?.src) {
                                        if (!media.some(m => m.url === node.attrs.src)) {
                                            media.push({ url: node.attrs.src, type: 'image', filename: null });
                                        }
                                    }
                                    if (node.content) walk(node.content);
                                }
                            };
                            walk(content.content);
                        }

                        // 3. Attachments in attachments_media order
                        const attachmentIds = (post.data.relationships?.attachments_media?.data || []).map(d => d.id);
                        for (const id of attachmentIds) {
                            const item = mediaById[id];
                            if (item) {
                                media.push({ url: urlOf(item), type: 'archive', filename: item.attributes.file_name || null });
                            }
                        }
                    }
                } catch {}
            }

            // DOM fallback: images
            if (!media.some(m => m.type === 'image')) {
                const postCard = document.querySelector('[data-tag="post-card"]');
                if (postCard) {
                    postCard.querySelectorAll('img[src*="patreonusercontent.com"]').forEach(img => {
                        if (!media.some(m => m.url === img.src)) {
                            media.push({ url: img.src, type: 'image', filename: null });
                        }
                    });
                }
            }

            // DOM fallback: attachments
            if (!media.some(m => m.type === 'archive')) {
                document.querySelectorAll('a[data-tag="post-attachment-link"]').forEach(a => {
                    if (a.href && !media.some(m => m.url === a.href)) {
                        const nameEl = a.querySelector('p');
                        media.push({ url: a.href, type: 'archive', filename: nameEl?.textContent?.trim() || null });
                    }
                });
            }

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

            const nextData = document.getElementById('__NEXT_DATA__');
            if (nextData) {
                try {
                    const data = JSON.parse(nextData.textContent);
                    const post = data?.props?.pageProps?.bootstrapEnvelope?.pageBootstrap?.post;
                    if (post?.data?.attributes) {
                        const attrs = post.data.attributes;
                        meta.postID = post.data.id || '';
                        meta.title = attrs.title || '';
                        meta.createdAt = attrs.published_at || attrs.created_at || '';
                        meta.modifiedAt = attrs.edited_at || null;

                        const tagData = post.data.relationships?.user_defined_tags?.data || [];
                        meta.tags = tagData
                            .map(t => (t.id || '').replace('user_defined;', ''))
                            .filter(t => t);
                    }
                    if (post?.included) {
                        for (const item of post.included) {
                            if (item.type === 'campaign' && item.attributes?.name) {
                                meta.authorName = item.attributes.name;
                                break;
                            }
                        }
                    }
                } catch {}
            }

            // Fallback: DOM scraping
            if (!meta.title) {
                const titleEl = document.querySelector('[data-tag="post-title"]');
                meta.title = titleEl?.textContent?.trim() || document.title;
            }
            if (!meta.authorName) {
                const authorEl = document.querySelector('[data-tag="post-card"] a[href*="patreon.com/"] > h3');
                meta.authorName = authorEl?.textContent?.trim() || '';
            }
            if (!meta.postID) {
                const match = location.pathname.match(/-(\\d+)(?:[^\\/]*)$/);
                meta.postID = match ? match[1] : '';
            }
            if (!meta.tags || !meta.tags.length) {
                meta.tags = [];
                document.querySelectorAll('a[data-tag="post-tag"] p').forEach(p => {
                    const tag = p.textContent?.trim();
                    if (tag) meta.tags.push(tag);
                });
            }
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
