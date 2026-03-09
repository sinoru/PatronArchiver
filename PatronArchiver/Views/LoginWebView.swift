import PatronArchiverKit
import SwiftUI
import WebKit

#if os(macOS)
struct LoginWebView: NSViewRepresentable {
    let url: URL
    let providerType: any PatronServiceProvider.Type
    let websiteDataStore: WKWebsiteDataStore
    var onLoginDetected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            providerType: providerType,
            websiteDataStore: websiteDataStore,
            onLoginDetected: onLoginDetected
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        context.coordinator.startObserving()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct LoginWebView: UIViewRepresentable {
    let url: URL
    let providerType: any PatronServiceProvider.Type
    let websiteDataStore: WKWebsiteDataStore
    var onLoginDetected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            providerType: providerType,
            websiteDataStore: websiteDataStore,
            onLoginDetected: onLoginDetected
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        context.coordinator.startObserving()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

extension LoginWebView {
    final class Coordinator: NSObject, WKHTTPCookieStoreObserver {
        let providerType: any PatronServiceProvider.Type
        let websiteDataStore: WKWebsiteDataStore
        let onLoginDetected: (() -> Void)?
        private var hasDetectedLogin = false

        init(
            providerType: any PatronServiceProvider.Type,
            websiteDataStore: WKWebsiteDataStore,
            onLoginDetected: (() -> Void)?
        ) {
            self.providerType = providerType
            self.websiteDataStore = websiteDataStore
            self.onLoginDetected = onLoginDetected
        }

        func startObserving() {
            websiteDataStore.httpCookieStore.add(self)
        }

        deinit {
            websiteDataStore.httpCookieStore.remove(self)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !hasDetectedLogin else { return }
            Task { @MainActor in
                let cookies = await cookieStore.allCookies()
                guard providerType.isLoggedIn(cookies: cookies) else { return }
                hasDetectedLogin = true
                onLoginDetected?()
            }
        }
    }
}
