import Foundation
import WebKit

enum MHTMLDumper {
    struct CollectedResource: Sendable {
        let url: URL
        let contentType: String
        let data: Data
    }

    static func createMHTML(from webView: WKWebView, dataStore: WKWebsiteDataStore) async throws -> Data {
        // 1. Collect resource URLs and HTML from DOM
        let collectScript = """
        (() => {
            const resources = new Set();

            // img src
            document.querySelectorAll('img[src]').forEach(img => {
                if (img.src) resources.add(img.src);
            });

            // img srcset
            document.querySelectorAll('img[srcset]').forEach(img => {
                img.srcset.split(',').forEach(entry => {
                    const url = entry.trim().split(/\\s+/)[0];
                    if (url) resources.add(url);
                });
            });

            // link stylesheets
            document.querySelectorAll('link[rel="stylesheet"][href]').forEach(link => {
                resources.add(link.href);
            });

            // video, audio, source
            document.querySelectorAll('video[src], audio[src], source[src]').forEach(el => {
                if (el.src) resources.add(el.src);
            });

            // picture source
            document.querySelectorAll('picture source[srcset]').forEach(source => {
                source.srcset.split(',').forEach(entry => {
                    const url = entry.trim().split(/\\s+/)[0];
                    if (url) resources.add(url);
                });
            });

            // inline style background-image
            document.querySelectorAll('[style*="url("]').forEach(el => {
                const matches = el.style.cssText.matchAll(/url\\(["']?([^"')]+)["']?\\)/g);
                for (const m of matches) {
                    try { resources.add(new URL(m[1], location.href).href); } catch {}
                }
            });

            const html = document.documentElement.outerHTML;
            return JSON.stringify({
                html: html,
                resources: Array.from(resources).filter(u => u.startsWith('http'))
            });
        })()
        """

        guard let jsonString = try await webView.evaluateJavaScript(collectScript) as? String,
              let jsonData = jsonString.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let html = result["html"] as? String,
              let resourceURLs = result["resources"] as? [String]
        else {
            throw MHTMLError.collectionFailed
        }

        guard let pageURL = webView.url else {
            throw MHTMLError.noPageURL
        }

        // 2. Download resources
        let resources = await downloadResources(
            urls: resourceURLs.compactMap { URL(string: $0) },
            dataStore: dataStore
        )

        // 3. Assemble MHTML
        return assembleMHTML(pageURL: pageURL, html: html, resources: resources)
    }

    @concurrent
    private static func downloadResources(
        urls: [URL],
        dataStore: WKWebsiteDataStore
    ) async -> [CollectedResource] {
        await withTaskGroup(of: CollectedResource?.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let request = await CookieHelper.configuredRequest(for: url, dataStore: dataStore)
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

    nonisolated private static func assembleMHTML(pageURL: URL, html: String, resources: [CollectedResource]) -> Data {
        let boundary = "----=_Part_\(UUID().uuidString)"
        var mhtml = ""

        // MHTML header
        mhtml += "From: <Saved by PatronArchiver>\r\n"
        mhtml += "Subject: \(pageURL.absoluteString)\r\n"
        mhtml += "MIME-Version: 1.0\r\n"
        mhtml += "Content-Type: multipart/related; boundary=\"\(boundary)\"\r\n"
        mhtml += "\r\n"

        // HTML part
        mhtml += "--\(boundary)\r\n"
        mhtml += "Content-Type: text/html; charset=\"utf-8\"\r\n"
        mhtml += "Content-Transfer-Encoding: quoted-printable\r\n"
        mhtml += "Content-Location: \(pageURL.absoluteString)\r\n"
        mhtml += "\r\n"
        mhtml += quotedPrintableEncode(html)
        mhtml += "\r\n"

        // Resource parts
        for resource in resources {
            mhtml += "--\(boundary)\r\n"
            mhtml += "Content-Type: \(resource.contentType)\r\n"
            mhtml += "Content-Transfer-Encoding: base64\r\n"
            mhtml += "Content-Location: \(resource.url.absoluteString)\r\n"
            mhtml += "\r\n"
            mhtml += resource.data.base64EncodedString(options: .lineLength76Characters)
            mhtml += "\r\n"
        }

        mhtml += "--\(boundary)--\r\n"

        return Data(mhtml.utf8)
    }

    nonisolated private static func quotedPrintableEncode(_ string: String) -> String {
        var result = ""
        var lineLength = 0

        for byte in string.utf8 {
            let encoded: String
            if byte == 0x0D || byte == 0x0A {
                encoded = String(UnicodeScalar(byte))
                lineLength = 0
            } else if byte == 0x3D { // '='
                encoded = "=3D"
            } else if byte >= 0x21 && byte <= 0x7E && byte != 0x3D {
                encoded = String(UnicodeScalar(byte))
            } else if byte == 0x20 || byte == 0x09 {
                encoded = String(UnicodeScalar(byte))
            } else {
                encoded = String(format: "=%02X", byte)
            }

            if lineLength + encoded.count > 75 {
                result += "=\r\n"
                lineLength = 0
            }
            result += encoded
            lineLength += encoded.count
        }

        return result
    }
}

enum MHTMLError: Error {
    case collectionFailed
    case noPageURL
}
