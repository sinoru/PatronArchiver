import PatronArchiverKit
import SwiftUI
import WebKit

struct MainView: View {
    private let patronArchiver: PatronArchiver

    @State private var webView: WKWebView
    @State private var urlText = ""
    @State private var isResolving = false
    #if os(iOS)
    @State private var showSettings = false
    #endif

    init(
        patronArchiver: PatronArchiver
    ) {
        self.patronArchiver = patronArchiver

        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.websiteDataStore = patronArchiver.websiteDataStore
        webViewConfiguration.defaultWebpagePreferences.preferredContentMode = .desktop

        self._webView = State(initialValue: WKWebView(
            frame: CGRect(origin: .zero, size: patronArchiver.renderSize),
            configuration: webViewConfiguration
        ))
    }

    @ViewBuilder
    private var urlTextField: some View {
        TextField("Enter post URL...", text: $urlText)
            .onSubmit { Task { await submitURL() } }
    }

    @ViewBuilder
    private var addButton: some View {
        if isResolving {
            ProgressView()
                #if os(macOS)
                .controlSize(.small)
                #endif
        } else {
            Button { Task { await submitURL() } } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(Text("Add"))
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            JobListView(archiver: patronArchiver)
                .background {
                    archiveWebViewArea
                }
                .onAppear {
                    patronArchiver.webView = webView
                    webView.load(URLRequest(url: URL(string: "about:blank")!))
                }
                .navigationTitle("PatronArchiver")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItemGroup(placement: .bottomBar) {
                        urlTextField
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        addButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                    #else
                    ToolbarItemGroup(placement: .principal) {
                        urlTextField
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                        addButton
                    }
                    #endif
                }
                #if os(iOS)
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(patronArchiver: patronArchiver)
                            .navigationTitle("Settings")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        showSettings = false
                                    }
                                }
                            }
                    }
                }
                #endif
                #if os(macOS)
                .frame(minWidth: 635, minHeight: 400)
                #endif
        }
    }

    @ViewBuilder
    private var archiveWebViewArea: some View {
        let renderSize = patronArchiver.renderSize

        ArchiveWebViewRepresentable(webView: webView)
            .frame(width: renderSize.width, height: renderSize.height)
            .scaleEffect(
                1.0 / max(renderSize.width, renderSize.height),
                anchor: .topLeading
            )
            .frame(width: 1, height: 1, alignment: .topLeading)
            .opacity(0.01)
            .allowsHitTesting(false)
    }

    private func submitURL() async {
        let urlString = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inputURL = URL(string: urlString), inputURL.scheme != nil else { return }

        isResolving = true
        defer { isResolving = false }

        let resolved = await URLResolver.resolve(inputURL)

        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { return }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return }

        patronArchiver.enqueue(url: url)
        urlText = ""
    }
}
