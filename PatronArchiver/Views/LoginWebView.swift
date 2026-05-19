import PatronArchiverKit
import SwiftUI
import WebKit

struct LoginWebView: View {
    let initialURL: URL
    let initialProviderType: any PatronServiceProviding.Type
    let websiteDataStore: WKWebsiteDataStore
    var onLoginDetected: (() -> Void)?

    @State private var currentURL: URL
    @State private var currentProviderType: any PatronServiceProviding.Type
    @State private var pendingAlternateProviderType: (any PatronServiceProviding.Type)?
    @State private var isShowingAlternateLoginAlert = false

    init(
        url: URL,
        providerType: any PatronServiceProviding.Type,
        websiteDataStore: WKWebsiteDataStore,
        onLoginDetected: (() -> Void)? = nil
    ) {
        self.initialURL = url
        self.initialProviderType = providerType
        self.websiteDataStore = websiteDataStore
        self.onLoginDetected = onLoginDetected
        _currentURL = State(initialValue: url)
        _currentProviderType = State(initialValue: providerType)
    }

    var body: some View {
        LoginWebViewRepresentable(
            url: currentURL,
            providerType: currentProviderType,
            websiteDataStore: websiteDataStore,
            onLoginDetected: handleLoginDetected
        )
        .alert(
            "Additional Sign-In",
            isPresented: $isShowingAlternateLoginAlert
        ) {
            Button("Skip", role: .cancel) {
                pendingAlternateProviderType = nil
                onLoginDetected?()
            }
            Button("Continue") {
                guard let alternate = pendingAlternateProviderType else { return }
                pendingAlternateProviderType = nil
                currentProviderType = alternate
                currentURL = alternate.loginURL
            }
        } message: {
            Text("Some \(currentProviderType.siteIdentifier) content is hosted on a separate domain. Sign in there as well to access it.")
        }
    }

    private func handleLoginDetected() {
        if let alternate = currentProviderType.alternateProviderType {
            pendingAlternateProviderType = alternate
            isShowingAlternateLoginAlert = true
        } else {
            onLoginDetected?()
        }
    }
}

private struct LoginWebViewRepresentable {
    let url: URL
    let providerType: any PatronServiceProviding.Type
    let websiteDataStore: WKWebsiteDataStore
    var onLoginDetected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            providerType: providerType,
            websiteDataStore: websiteDataStore,
            onLoginDetected: onLoginDetected
        )
    }
}

#if canImport(AppKit)
extension LoginWebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.startObserving()
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(providerType: providerType, url: url, in: nsView)
    }
}
#elseif canImport(UIKit)
extension LoginWebViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.startObserving()
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(providerType: providerType, url: url, in: uiView)
    }
}
#endif

extension LoginWebViewRepresentable {
    final class Coordinator: NSObject, WKHTTPCookieStoreObserver {
        private var providerType: any PatronServiceProviding.Type
        let websiteDataStore: WKWebsiteDataStore
        let onLoginDetected: (() -> Void)?
        private var hasDetectedLogin = false
        private var lastRequestedURL: URL?

        init(
            providerType: any PatronServiceProviding.Type,
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

        isolated deinit {
            websiteDataStore.httpCookieStore.remove(self)
        }

        func load(_ url: URL, in webView: WKWebView) {
            lastRequestedURL = url
            webView.load(URLRequest(url: url))
        }

        func update(
            providerType newProviderType: any PatronServiceProviding.Type,
            url: URL,
            in webView: WKWebView
        ) {
            if ObjectIdentifier(newProviderType) != ObjectIdentifier(providerType) {
                providerType = newProviderType
                hasDetectedLogin = false
            }
            if lastRequestedURL != url {
                load(url, in: webView)
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !hasDetectedLogin else { return }
            Task {
                let allCookies = await cookieStore.allCookies()
                guard providerType.isLoggedIn(cookies: allCookies) else { return }
                hasDetectedLogin = true
                onLoginDetected?()
            }
        }
    }
}
