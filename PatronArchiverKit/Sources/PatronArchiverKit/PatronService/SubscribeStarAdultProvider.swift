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

        // Cloudflare email protection: the email is XOR-obfuscated in a data-cfemail attribute
        // e.g. <a href="/cdn-cgi/l/email-protection" data-cfemail="hex_encoded">
        let cfPattern = #"settings_login-label">Email</div>\s*<div class="settings_login-value">.*?data-cfemail="([0-9a-fA-F]+)""#
        if let cfRange = html.range(of: cfPattern, options: .regularExpression) {
            let match = html[cfRange]
            if let attrStart = match.range(of: "data-cfemail=\""),
               let attrEnd = match.range(of: "\"", range: attrStart.upperBound..<match.endIndex) {
                let encoded = String(match[attrStart.upperBound..<attrEnd.lowerBound])
                if let email = decodeCFEmail(encoded), !email.isEmpty {
                    return AccountInfo(displayName: email)
                }
            }
        }

        // Fallback: plain text email (no Cloudflare obfuscation)
        let plainPattern = #"settings_login-label">Email</div>\s*<div class="settings_login-value">([^<]+)</div>"#
        if let range = html.range(of: plainPattern, options: .regularExpression) {
            let match = html[range]
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

    /// Decodes a Cloudflare email-protected hex string.
    ///
    /// The first byte is the XOR key; each subsequent byte is XOR'd with the key
    /// to recover the original character.
    private static func decodeCFEmail(_ encoded: String) -> String? {
        let chars = Array(encoded)
        guard chars.count >= 4, chars.count.isMultiple(of: 2) else { return nil }
        guard let key = UInt8(String(chars[0...1]), radix: 16) else { return nil }
        var result = ""
        for i in stride(from: 2, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            result.append(Character(UnicodeScalar(byte ^ key)))
        }
        return result
    }

    static func isLoggedIn(cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.name == "auth_tracker_code" }
    }

    func preloadContent(in webView: WKWebView) async throws {
        // Do nothing
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

            return media;
        })()
        """
        guard let array = try await evaluateJavaScript(script, in: webView) as? [[String: Any]] else {
            return []
        }
        let referrerURL = webView.url
        return array.compactMap { MediaItem(from: $0, referrerURL: referrerURL) }
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

            // Title from first child of trix-content (h1 or div)
            const titleEl = document.querySelector('.trix-content > :first-child');
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

            return meta;
        })()
        """
        guard let dict = try await evaluateJavaScript(script, in: webView) as? [String: Any] else {
            throw ProviderError.metadataExtractionFailed
        }

        let createdAt = Self.parseLocalizedDate(
            dict["createdAt"] as? String,
            timeZone: timeZone
        ) ?? Date()

        return PostMetadata(
            siteIdentifier: Self.siteIdentifier,
            postID: dict["postID"] as? String ?? "",
            title: dict["title"] as? String ?? "",
            authorName: dict["authorName"] as? String ?? "",
            createdAt: createdAt,
            modifiedAt: nil,
            tags: dict["tags"] as? [String] ?? [],
            originalURL: webView.url ?? Self.loginURL,
            redirectChain: []
        )
    }

    private static func parseLocalizedDate(
        _ string: String?,
        timeZone: TimeZone?
    ) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd, yyyy hh:mm a"
        formatter.timeZone = timeZone ?? .gmt
        return formatter.date(from: string)
    }
}
