import WebKit

enum Preloader {
    static func preload(in webView: WKWebView, scrollDelay: Double = 300) async throws {
        let script = """
        (async () => {
            const delay = \(scrollDelay);
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
            const step = Math.floor(viewportHeight * 0.8);
            let currentPosition = 0;
            const maxScroll = document.documentElement.scrollHeight;

            // Scroll down step by step
            while (currentPosition < maxScroll) {
                window.scrollBy(0, step);
                currentPosition += step;

                await new Promise(r => requestAnimationFrame(() => {
                    setTimeout(r, delay);
                }));

                // Re-check scrollHeight in case content loaded
                const newMax = document.documentElement.scrollHeight;
                if (newMax > maxScroll) {
                    // Content grew, keep going
                }
            }

            // Scroll back to top
            window.scrollTo(0, 0);
            await new Promise(r => setTimeout(r, delay));

            // Wait for all images to complete
            const waitForImages = async () => {
                const images = Array.from(document.querySelectorAll('img'));
                const incomplete = images.filter(img => !img.complete && img.src);
                for (const img of incomplete) {
                    img.scrollIntoView({ behavior: 'instant', block: 'center' });
                    await new Promise(r => setTimeout(r, delay));
                    // Wait for this image
                    if (!img.complete) {
                        await new Promise((resolve) => {
                            img.addEventListener('load', resolve, { once: true });
                            img.addEventListener('error', resolve, { once: true });
                            setTimeout(resolve, 5000); // max 5s per image
                        });
                    }
                }
            };

            await waitForImages();
            window.scrollTo(0, 0);
            return true;
        })()
        """

        _ = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
    }
}
