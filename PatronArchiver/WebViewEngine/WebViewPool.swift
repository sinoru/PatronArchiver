import WebKit

#if os(iOS)
import UIKit
#endif

class WebViewPool {
    private var available: [WKWebView] = []
    private var inUse: Set<ObjectIdentifier> = []
    private let configuration: WKWebViewConfiguration
    private let renderWidth: CGFloat
    private let renderHeight: CGFloat = 1080

    #if os(iOS)
    private var renderWindow: UIWindow?
    #endif

    init(poolSize: Int = 3, renderWidth: CGFloat = 1920) {
        self.renderWidth = renderWidth

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        self.configuration = config

        for _ in 0..<poolSize {
            let webView = makeWebView()
            available.append(webView)
        }
    }

    private func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight), configuration: configuration)
        #if os(iOS)
        attachToRenderWindow(webView)
        #endif
        return webView
    }

    #if os(iOS)
    private func attachToRenderWindow(_ webView: WKWebView) {
        if renderWindow == nil, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
            window.rootViewController = UIViewController()
            window.isHidden = true
            window.makeKeyAndVisible()
            renderWindow = window
        }
        renderWindow?.rootViewController?.view.addSubview(webView)
    }
    #endif

    func acquire() async -> WKWebView {
        if let webView = available.popLast() {
            inUse.insert(ObjectIdentifier(webView))
            return webView
        }
        let webView = makeWebView()
        inUse.insert(ObjectIdentifier(webView))
        return webView
    }

    func release(_ webView: WKWebView) {
        inUse.remove(ObjectIdentifier(webView))
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        available.append(webView)
    }

    var sharedDataStore: WKWebsiteDataStore {
        configuration.websiteDataStore
    }
}
