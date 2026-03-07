import Foundation
import WebKit

// MARK: - Errors

enum MHTMLError: Error {
    case collectionFailed
    case noPageURL
}

// MARK: - Public API

extension WKWebView {
    /// RFC 2557 MHTML 아카이브 생성
    func mhtml(dataStore: WKWebsiteDataStore, userAgent: String? = nil) async throws -> Data {
        guard let pageURL = url else {
            throw MHTMLError.noPageURL
        }

        // 1. Collect resource URLs, HTML, title, and iframe info from DOM
        let collectResult = try await collectPageResources()

        // 2. First-pass: download all resources discovered by JS
        let firstPassResources = await downloadResources(
            urls: collectResult.resourceURLs.compactMap { URL(string: $0) },
            dataStore: dataStore,
            userAgent: userAgent
        )

        // 3. Second-pass: extract CSS subresource URLs and download missing ones
        let alreadyDownloaded = Set(firstPassResources.map(\.url.absoluteString))
        let cssSubresourceURLs = await extractCSSSubresourceURLs(from: firstPassResources)
            .filter { !alreadyDownloaded.contains($0.absoluteString) }

        let secondPassResources = await downloadResources(
            urls: cssSubresourceURLs,
            dataStore: dataStore,
            userAgent: userAgent
        )

        // 4. Collect iframe sub-document content
        let iframeResources = await collectIframeResources(
            iframes: collectResult.iframes,
            dataStore: dataStore,
            userAgent: userAgent
        )

        let allResources = firstPassResources + secondPassResources + iframeResources

        // 5. Assemble MHTML
        return await assembleMHTML(
            pageURL: pageURL,
            title: collectResult.title,
            html: collectResult.html,
            resources: allResources
        )
    }

    /// 전체 페이지 높이 PDF 생성
    func fullPagePDF() async throws -> Data {
        let contentHeight = try await evaluateJavaScript(
            "document.documentElement.scrollHeight"
        ) as? Double ?? 0

        let config = WKPDFConfiguration()
        config.rect = CGRect(
            x: 0,
            y: 0,
            width: frame.width,
            height: contentHeight
        )

        return try await pdf(configuration: config)
    }
}

// MARK: - JS Resource Collection

private struct CollectResult {
    let html: String
    let title: String
    let resourceURLs: [String]
    let iframes: [IframeInfo]
}

private struct IframeInfo {
    let url: String
    let html: String? // nil for cross-origin iframes
}

private extension WKWebView {
    func collectPageResources() async throws -> CollectResult {
        let script = """
        (() => {
            const resources = new Set();

            // --- Collect resource URLs from DOM elements ---

            // img src
            document.querySelectorAll('img[src]').forEach(img => {
                if (img.src && !img.src.startsWith('data:')) resources.add(img.src);
            });

            // img srcset
            document.querySelectorAll('img[srcset]').forEach(img => {
                img.srcset.split(',').forEach(entry => {
                    const url = entry.trim().split(/\\s+/)[0];
                    if (url && !url.startsWith('data:')) {
                        try { resources.add(new URL(url, location.href).href); } catch {}
                    }
                });
            });

            // link stylesheets
            document.querySelectorAll('link[rel="stylesheet"][href]').forEach(link => {
                resources.add(link.href);
            });

            // video, audio, source
            document.querySelectorAll('video[src], audio[src], source[src]').forEach(el => {
                if (el.src && !el.src.startsWith('data:')) resources.add(el.src);
            });

            // picture source srcset
            document.querySelectorAll('picture source[srcset]').forEach(source => {
                source.srcset.split(',').forEach(entry => {
                    const url = entry.trim().split(/\\s+/)[0];
                    if (url && !url.startsWith('data:')) {
                        try { resources.add(new URL(url, location.href).href); } catch {}
                    }
                });
            });

            // --- Collect URLs from CSS rules (inline <style> and linked stylesheets) ---

            function extractURLsFromRules(rules, baseHref) {
                for (let i = 0; i < rules.length; i++) {
                    const rule = rules[i];
                    const urlMatches = rule.cssText.matchAll(/url\\(["']?([^"')]+)["']?\\)/g);
                    for (const m of urlMatches) {
                        if (m[1].startsWith('data:')) continue;
                        try {
                            resources.add(new URL(m[1], baseHref).href);
                        } catch {}
                    }
                    // Recurse into nested rules (@media, @supports, etc.)
                    if (rule.cssRules) extractURLsFromRules(rule.cssRules, baseHref);
                }
            }

            for (let i = 0; i < document.styleSheets.length; i++) {
                const sheet = document.styleSheets[i];
                try {
                    const baseHref = sheet.href || location.href;
                    extractURLsFromRules(sheet.cssRules, baseHref);
                } catch {
                    // Cross-origin stylesheet — can't access rules; Swift 2nd pass handles it
                }
            }

            // inline style background-image
            document.querySelectorAll('[style*="url("]').forEach(el => {
                const matches = el.style.cssText.matchAll(/url\\(["']?([^"')]+)["']?\\)/g);
                for (const m of matches) {
                    if (m[1].startsWith('data:')) continue;
                    try { resources.add(new URL(m[1], location.href).href); } catch {}
                }
            });

            // --- Serialize mutable stylesheets (styled-components, etc.) ---

            document.querySelectorAll('style').forEach(style => {
                if (!style.sheet) return;
                try {
                    const cssomText = Array.from(style.sheet.cssRules).map(r => r.cssText).join('\\n');
                    const sourceText = style.textContent.trim();
                    // Replace if CSSOM differs from source (mutable stylesheet)
                    if (cssomText && cssomText !== sourceText) {
                        style.textContent = cssomText;
                    }
                } catch {}
            });

            // --- Adopted stylesheets ---

            if (document.adoptedStyleSheets && document.adoptedStyleSheets.length > 0) {
                for (const sheet of document.adoptedStyleSheets) {
                    try {
                        const cssText = Array.from(sheet.cssRules).map(r => r.cssText).join('\\n');
                        if (cssText) {
                            const styleEl = document.createElement('style');
                            styleEl.setAttribute('data-adopted-stylesheet', '');
                            styleEl.textContent = cssText;
                            document.head.appendChild(styleEl);
                        }
                    } catch {}
                }
            }

            // --- Escape </style> inside <style> tags to prevent MHTML parser breakage ---

            document.querySelectorAll('style').forEach(style => {
                if (style.textContent.includes('</style')) {
                    style.textContent = style.textContent.replace(/<\\/style/gi, '\\\\3C /style');
                }
            });

            // --- Collect iframe sub-documents ---

            const iframes = [];
            document.querySelectorAll('iframe[src]').forEach(iframe => {
                if (!iframe.src || iframe.src.startsWith('data:') || iframe.src === 'about:blank') return;
                const info = { url: iframe.src, html: null };
                try {
                    if (iframe.contentDocument && iframe.contentDocument.documentElement) {
                        info.html = iframe.contentDocument.documentElement.outerHTML;
                    }
                } catch {}
                iframes.push(info);
            });

            const html = document.documentElement.outerHTML;
            return JSON.stringify({
                html: html,
                title: document.title || '',
                resources: Array.from(resources).filter(u => u.startsWith('http')),
                iframes: iframes
            });
        })()
        """

        guard let jsonString = try await evaluateJavaScript(script) as? String,
              let jsonData = jsonString.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let html = result["html"] as? String,
              let resourceURLs = result["resources"] as? [String]
        else {
            throw MHTMLError.collectionFailed
        }

        let title = result["title"] as? String ?? ""

        var iframes: [IframeInfo] = []
        if let iframeArray = result["iframes"] as? [[String: Any]] {
            for item in iframeArray {
                guard let url = item["url"] as? String else { continue }
                let html = item["html"] as? String
                iframes.append(IframeInfo(url: url, html: html))
            }
        }

        return CollectResult(
            html: html,
            title: title,
            resourceURLs: resourceURLs,
            iframes: iframes
        )
    }
}

// MARK: - Resource Download

private struct CollectedResource: Sendable {
    let url: URL
    let contentType: String
    let data: Data
}

@concurrent
private func downloadResources(
    urls: [URL],
    dataStore: WKWebsiteDataStore,
    userAgent: String? = nil
) async -> [CollectedResource] {
    // Batch urlRequest creation to minimize main actor hops
    var requests: [URL: URLRequest] = [:]
    for url in urls {
        requests[url] = await dataStore.urlRequest(for: url, userAgent: userAgent)
    }

    return await withTaskGroup(of: CollectedResource?.self) { group in
        for url in urls {
            let request = requests[url]!
            group.addTask {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let contentType = (response as? HTTPURLResponse)?
                        .value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
                    return CollectedResource(url: url, contentType: contentType, data: data)
                } catch {
                    return nil
                }
            }
        }
        var results: [CollectedResource] = []
        for await resource in group {
            if let resource { results.append(resource) }
        }
        return results
    }
}

// MARK: - Iframe Sub-document Collection

@concurrent
private func collectIframeResources(
    iframes: [IframeInfo],
    dataStore: WKWebsiteDataStore,
    userAgent: String? = nil
) async -> [CollectedResource] {
    // Batch urlRequest creation for cross-origin iframes
    var requestsBuilder: [String: URLRequest] = [:]
    for iframe in iframes where iframe.html == nil {
        guard let url = URL(string: iframe.url) else { continue }
        requestsBuilder[iframe.url] = await dataStore.urlRequest(for: url, userAgent: userAgent)
    }
    let requests = requestsBuilder

    return await withTaskGroup(of: CollectedResource?.self) { group in
        for iframe in iframes {
            let iframeURL = iframe.url
            let iframeHTML = iframe.html
            group.addTask {
                guard let url = URL(string: iframeURL) else { return nil }

                if let html = iframeHTML {
                    // Same-origin: already captured from contentDocument
                    return CollectedResource(
                        url: url,
                        contentType: "text/html; charset=utf-8",
                        data: Data(html.utf8)
                    )
                } else {
                    // Cross-origin: download via URLSession
                    guard let request = requests[iframeURL] else { return nil }
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let contentType = (response as? HTTPURLResponse)?
                            .value(forHTTPHeaderField: "Content-Type") ?? "text/html"
                        return CollectedResource(
                            url: url, contentType: contentType, data: data
                        )
                    } catch {
                        return nil
                    }
                }
            }
        }
        var results: [CollectedResource] = []
        for await resource in group {
            if let resource { results.append(resource) }
        }
        return results
    }
}

// MARK: - CSS Subresource Extraction (2nd Pass)

@concurrent
private func extractCSSSubresourceURLs(from resources: [CollectedResource]) async -> [URL] {
    let cssURLPattern = /url\(["']?([^"')]+)["']?\)/

    var discovered: [URL] = []
    for resource in resources {
        // Only parse CSS files
        guard resource.contentType.hasPrefix("text/css") else { continue }
        guard let cssText = String(data: resource.data, encoding: .utf8) else { continue }

        for match in cssText.matches(of: cssURLPattern) {
            let urlString = String(match.1)
            if urlString.hasPrefix("data:") { continue }
            if let resolved = URL(string: urlString, relativeTo: resource.url)?.absoluteURL {
                discovered.append(resolved)
            }
        }
    }

    // Deduplicate
    var seen = Set<String>()
    return discovered.filter { seen.insert($0.absoluteString).inserted }
}

// MARK: - MHTML Assembly

@concurrent
private func assembleMHTML(
    pageURL: URL,
    title: String,
    html: String,
    resources: [CollectedResource]
) async -> Data {
    let boundary = "----=_Part_\(UUID().uuidString)"
    let dateString = MHTMLDateFormatter.shared.string(from: Date())

    var mhtml = Data()

    func append(_ string: String) {
        mhtml.append(contentsOf: string.utf8)
    }

    // MHTML header (RFC 2557 + Chromium conventions)
    append("From: <Saved by PatronArchiver>\r\n")
    append("Snapshot-Content-Location: \(pageURL.absoluteString)\r\n")
    append("Subject: \(title.isEmpty ? pageURL.absoluteString : title)\r\n")
    append("Date: \(dateString)\r\n")
    append("MIME-Version: 1.0\r\n")
    append("Content-Type: multipart/related; type=\"text/html\"; boundary=\"\(boundary)\"\r\n")
    append("\r\n")

    // HTML part
    append("--\(boundary)\r\n")
    append("Content-Type: text/html; charset=\"utf-8\"\r\n")
    append("Content-Transfer-Encoding: quoted-printable\r\n")
    append("Content-Location: \(pageURL.absoluteString)\r\n")
    append("\r\n")
    mhtml.append(quotedPrintableEncode(html))
    append("\r\n")

    // Resource parts
    for resource in resources {
        append("--\(boundary)\r\n")
        append("Content-Type: \(resource.contentType)\r\n")

        if isTextBasedContentType(resource.contentType),
           let text = String(data: resource.data, encoding: .utf8)
        {
            append("Content-Transfer-Encoding: quoted-printable\r\n")
            append("Content-Location: \(resource.url.absoluteString)\r\n")
            append("\r\n")
            mhtml.append(quotedPrintableEncode(text))
        } else {
            append("Content-Transfer-Encoding: base64\r\n")
            append("Content-Location: \(resource.url.absoluteString)\r\n")
            append("\r\n")
            mhtml.append(resource.data.base64EncodedData(options: .lineLength76Characters))
        }
        append("\r\n")
    }

    append("--\(boundary)--\r\n")

    return mhtml
}

/// Determines whether the given Content-Type should use quoted-printable encoding.
nonisolated private func isTextBasedContentType(_ contentType: String) -> Bool {
    let mimeType = contentType
        .split(separator: ";").first?
        .trimmingCharacters(in: .whitespaces)
        .lowercased() ?? ""

    if mimeType.hasPrefix("text/") { return true }
    if mimeType == "image/svg+xml" { return true }
    if mimeType == "application/javascript" { return true }
    if mimeType == "application/json" { return true }
    if mimeType == "application/xml" { return true }
    if mimeType.hasSuffix("+xml") { return true }
    return false
}

// MARK: - Quoted-Printable Encoding (RFC 2045)

private nonisolated let crlf: [UInt8] = [0x0D, 0x0A]
private nonisolated let softLineBreak: [UInt8] = [0x3D, 0x0D, 0x0A] // "=\r\n"
private nonisolated let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

nonisolated private func quotedPrintableEncode(_ string: String) -> Data {
    let bytes = Array(string.utf8)
    var result = Data()
    result.reserveCapacity(bytes.count + bytes.count / 10)
    var lineLength = 0
    let count = bytes.count

    var i = 0
    while i < count {
        let byte = bytes[i]

        // CR LF — emit line break and reset
        if byte == 0x0D, i + 1 < count, bytes[i + 1] == 0x0A {
            result.append(contentsOf: crlf)
            lineLength = 0
            i += 2
            continue
        }

        // Bare LF — normalize to CRLF
        if byte == 0x0A {
            result.append(contentsOf: crlf)
            lineLength = 0
            i += 1
            continue
        }

        // Bare CR — normalize to CRLF
        if byte == 0x0D {
            result.append(contentsOf: crlf)
            lineLength = 0
            i += 1
            continue
        }

        // Determine the encoded form
        let encoded: [UInt8]
        if byte == 0x3D { // '='
            encoded = [0x3D, 0x33, 0x44] // "=3D"
        } else if byte == 0x20 || byte == 0x09 { // space or tab
            // RFC 2045: trailing whitespace at line end must be encoded
            let isTrailing = isTrailingWhitespace(bytes: bytes, from: i)
            if isTrailing {
                encoded = [0x3D, hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]]
            } else {
                encoded = [byte]
            }
        } else if byte >= 0x21, byte <= 0x7E {
            encoded = [byte]
        } else {
            encoded = [0x3D, hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]]
        }

        // Soft line break if needed (max 76 chars including soft break "=")
        if lineLength + encoded.count > 75 {
            result.append(contentsOf: softLineBreak)
            lineLength = 0
        }

        result.append(contentsOf: encoded)
        lineLength += encoded.count
        i += 1
    }

    return result
}

/// Check if the whitespace byte at `from` is trailing (followed only by whitespace until line end or EOF).
nonisolated private func isTrailingWhitespace(bytes: [UInt8], from index: Int) -> Bool {
    var j = index + 1
    while j < bytes.count {
        let b = bytes[j]
        if b == 0x0D || b == 0x0A {
            return true
        }
        if b != 0x20 && b != 0x09 {
            return false
        }
        j += 1
    }
    // EOF counts as trailing
    return true
}

// MARK: - RFC 2822 Date Formatter

private enum MHTMLDateFormatter {
    nonisolated static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
