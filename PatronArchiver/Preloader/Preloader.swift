import WebKit

enum Preloader {
    static func preload(in webView: WKWebView, scrollDelay: Double = 300) async throws {
        let script = """
        const delay = \(scrollDelay);
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
        const step = Math.floor(viewportHeight * 0.5);
        let currentPosition = 0;
        let maxScroll = document.documentElement.scrollHeight;

        // Scroll through entire page slowly to trigger lazy loading
        while (currentPosition < maxScroll) {
            window.scrollBy(0, step);
            currentPosition += step;

            // Wait for rendering frame + delay for IntersectionObserver to fire
            await new Promise(r => requestAnimationFrame(() => {
                setTimeout(r, delay);
            }));

            // Re-check scrollHeight in case content loaded
            maxScroll = document.documentElement.scrollHeight;
        }

        // Wait at bottom for any final lazy loads
        await new Promise(r => setTimeout(r, 1000));

        // Scroll back to top slowly (triggers elements near top again)
        window.scrollTo(0, 0);
        await new Promise(r => setTimeout(r, 1000));

        // Trigger lazy images that still have no src.
        // Some IntersectionObserver-based lazy loaders only fire when
        // the element enters the viewport; scroll each one into view
        // and wait for the framework to set src.
        const triggerLazyImages = async () => {
            const images = Array.from(document.querySelectorAll('img'));
            const noSrc = images.filter(img => !img.getAttribute('src'));
            for (const img of noSrc) {
                img.scrollIntoView({ behavior: 'instant', block: 'center' });
                // Wait for IntersectionObserver callback + framework setState
                await new Promise(r => requestAnimationFrame(() => {
                    setTimeout(r, delay);
                }));
                // If src was set, wait a bit more for the load to start
                if (img.getAttribute('src')) {
                    await new Promise(r => setTimeout(r, delay));
                }
            }
        };

        await triggerLazyImages();

        // Wait for all images to complete loading
        const waitForLoadedImages = async () => {
            const images = Array.from(document.querySelectorAll('img'));
            const incomplete = images.filter(img => img.src && !img.complete);
            for (const img of incomplete) {
                img.scrollIntoView({ behavior: 'instant', block: 'center' });
                await new Promise(r => setTimeout(r, delay));
                if (!img.complete) {
                    await new Promise((resolve) => {
                        img.addEventListener('load', resolve, { once: true });
                        img.addEventListener('error', resolve, { once: true });
                        setTimeout(resolve, 5000);
                    });
                }
            }
        };

        await waitForLoadedImages();

        // Second pass: new images may have appeared after lazy content loaded
        await triggerLazyImages();
        await waitForLoadedImages();

        // Final settle: wait for all CSS transitions to complete
        window.scrollTo(0, 0);
        await new Promise(r => setTimeout(r, 2000));

        return true;
        """

        _ = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
    }
}
