import SwiftUI
import WebKit
import PatronArchiverKit

struct MainView: View {
    @Bindable private var patronArchiver: PatronArchiver

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
                .safeAreaInset(edge: .bottom) {
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
                ToolbarItem(placement: .bottomBar) {
                    urlTextField
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                ToolbarItem(placement: .bottomBar) {
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
                ToolbarItem(placement: .principal) {
                    urlTextField
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                ToolbarItem(placement: .principal) {
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
        let previewHeight: CGFloat = 200
        let scale = previewHeight / renderSize.height
        let previewWidth = renderSize.width * scale

        ArchiveWebViewRepresentable(webView: webView)
            .frame(width: renderSize.width, height: renderSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: previewWidth, height: previewHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .padding()
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
