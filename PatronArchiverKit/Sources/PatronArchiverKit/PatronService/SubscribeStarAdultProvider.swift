import Foundation
import WebKit

struct SubscribeStarAdultProvider: PatronServiceProvider {
    static let matchPatterns: [any RegexComponent] = [
        /https:\/\/subscribestar\.adult\/posts\/.+/,
    ]
    static let loginURL = URL(string: "https://subscribestar.adult/login")!
    static let accountCheckURL = URL(string: "https://subscribestar.adult/account/settings")!
    static let siteIdentifier = "SubscribeStar.adult"

    static func parseAccountInfo(from data: Data) -> AccountInfo? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        // Extract email from login credentials section:
        // <div class="settings_login-label">Email</div>
        // <div class="settings_login-value">user@example.com</div>
        let pattern = #"settings_login-label">Email</div>\s*<div class="settings_login-value">([^<]+)</div>"#
        if let range = html.range(of: pattern, options: .regularExpression) {
            let match = html[range]
            // Extract the email between the last > and </div>
            if let valueStart = match.range(of: "settings_login-value\">"),
               let valueEnd = match.range(of: "</div>", range: valueStart.upperBound..<match.endIndex) {
                let email = String(match[valueStart.upperBound..<valueEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !email.isEmpty {
                    return AccountInfo(displayName: email)
                }
            }
        }
        return nil
    }

    func checkLoginStatus(in webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(
            "document.querySelector('.top_bar-user_name') !== null",
            in: webView
        )
        return result as? Bool ?? false
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Load uploads if they are lazily loaded
        _ = try? await evaluateJavaScript("""
            (() => {
                document.querySelectorAll('[data-autoload="false"][data-identifier*="uploads"]').forEach(el => {
                    const url = el.getAttribute('data-url');
                    if (url) {
                        fetch(url, { credentials: 'same-origin' })
                            .then(r => r.text())
                            .then(html => { el.innerHTML = html; el.setAttribute('data-autoload', 'true'); });
                    }
                });
            })()
        """, in: webView)
        try? await Task.sleep(for: .seconds(1))

        // Load all comments
        for _ in 0..<UInt16.max {
            let result = try await evaluateJavaScript("""
                (() => {
                    const before = document.querySelectorAll('.comments-row[data-id]').length;
                    let clicked = 0;
                    document.querySelectorAll('[data-role="ajax_container-ajax_button"]').forEach(btn => {
                        if (btn.textContent.includes('Load more') || btn.textContent.includes('Show more')) {
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

            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                let current = try await evaluateJavaScript(
                    "document.querySelectorAll('.comments-row[data-id]').length",
                    in: webView
                ) as? Int ?? 0
                if current > before { break }
            }
        }
    }

    func resolveTimeZone(in webView: WKWebView) async throws -> TimeZone? {
        let script = """
            const resp = await fetch('/account/settings', { credentials: 'same-origin' });
            const html = await resp.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const sel = doc.querySelector('select[name="timezone"] option[selected]');
            if (!sel) return null;
            const m = sel.textContent.match(/GMT([+-]\\d{2}):(\\d{2})/);
            if (!m) return null;
            const hours = parseInt(m[1]);
            const mins = parseInt(m[2]);
            return hours * 3600 + (hours < 0 ? -mins : mins) * 60;
        """
        guard let seconds = try await callAsyncJavaScript(script, in: webView) as? Int else {
            return nil
        }
        return TimeZone(secondsFromGMT: seconds)
    }

    func extractMediaURLs(in webView: WKWebView) async throws -> [MediaItem] {
        let script = """
        (() => {
            const media = [];

            // Gallery images from data-gallery JSON attribute
            const postUploads = document.querySelector('.post-body .post-uploads:not(.for-youtube)');
            const galleryEl = postUploads?.querySelector('.uploads-images');
            if (galleryEl) {
                try {
                    const gallery = JSON.parse(galleryEl.getAttribute('data-gallery'));
                    for (const item of gallery) {
                        if (item.url) {
                            media.push({
                                url: new URL(item.url, location.href).href,
                                type: item.type || 'image',
                                filename: item.original_filename || null,
                            });
                        }
                    }
                } catch {}
            }

            // Inline images in trix-content (not already captured)
            document.querySelectorAll('.trix-content img').forEach(img => {
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

    func extractMetadata(
        in webView: WKWebView,
        timeZone: TimeZone?
    ) async throws -> PostMetadata {
        let script = """
        (() => {
            const meta = {};

            // Post ID from URL
            const pathMatch = location.pathname.match(/posts\\/(\\d+)/);
            meta.postID = pathMatch ? pathMatch[1] : '';

            // Title from trix-content h1
            const titleEl = document.querySelector('.trix-content h1');
            meta.title = titleEl?.textContent?.trim() || document.title;

            // Author from sidebar star_link-name
            const authorEl = document.querySelector('.star_link-name');
            meta.authorName = authorEl?.textContent?.trim() || '';

            // Date from section-title_date (localized, e.g. "Mar 03, 2026 08:10 am")
            const dateEl = document.querySelector('.section-title_date');
            meta.createdAt = dateEl?.textContent?.trim() || '';

            // Tags from post_tag links
            meta.tags = Array.from(document.querySelectorAll('a.post_tag'))
                .map(a => a.textContent.trim())
                .filter(t => t.length > 0);

            return JSON.stringify(meta);
        })()
        """
        guard let jsonString = try await evaluateJavaScript(script, in: webView) as? String,
              let metadata = parseMetadataJSON(
                  jsonString,
                  siteIdentifier: Self.siteIdentifier,
                  originalURL: webView.url ?? Self.loginURL,
                  redirectChain: [],
                  timeZone: timeZone
              )
        else {
            throw ProviderError.metadataExtractionFailed
        }
        return metadata
    }
}
