import SwiftUI
import WebKit

#if os(macOS)
struct LoginWebView: NSViewRepresentable {
    let url: URL
    let providerType: any PatronServiceProvider.Type
    var onLoginDetected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(providerType: providerType, onLoginDetected: onLoginDetected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct LoginWebView: UIViewRepresentable {
    let url: URL
    let providerType: any PatronServiceProvider.Type
    var onLoginDetected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(providerType: providerType, onLoginDetected: onLoginDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

extension LoginWebView {
    final class Coordinator: NSObject, WKNavigationDelegate {
        let providerType: any PatronServiceProvider.Type
        let onLoginDetected: (() -> Void)?
        private var hasDetectedLogin = false

        init(providerType: any PatronServiceProvider.Type, onLoginDetected: (() -> Void)?) {
            self.providerType = providerType
            self.onLoginDetected = onLoginDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasDetectedLogin,
                  let currentURL = webView.url,
                  currentURL != providerType.loginURL
            else { return }
            let provider = providerType.init()
            Task { @MainActor in
                guard let isLoggedIn = try? await provider.checkLoginStatus(in: webView),
                      isLoggedIn else { return }
                hasDetectedLogin = true
                onLoginDetected?()
            }
        }
    }
}
