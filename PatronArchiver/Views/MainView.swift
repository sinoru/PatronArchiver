import SwiftUI
import WebKit

struct MainView: View {
    @State private var archiver: PatronArchiver
    @State private var settings: AppSettings
    @State private var webView: WKWebView
    @State private var urlText = ""
    @State private var isResolving = false
    #if os(iOS)
    @State private var showSettings = false
    #endif

    init(settings: AppSettings) {
        self._settings = State(initialValue: settings)
        let archiver = PatronArchiver(settings: settings)
        self._archiver = State(initialValue: archiver)
        self._webView = State(initialValue: WKWebView(
            frame: CGRect(origin: .zero, size: archiver.renderSize),
            configuration: archiver.webViewConfiguration
        ))
    }

    var body: some View {
        NavigationStack {
            JobListView(archiver: archiver)
                .safeAreaInset(edge: .bottom) {
                    archiveWebViewArea
                }
            .onAppear {
                archiver.webView = webView
                webView.load(URLRequest(url: URL(string: "about:blank")!))
            }
            .navigationTitle("PatronArchiver")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    TextField("Enter post URL...", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await submitURL() } }
                }
                ToolbarItem(placement: .bottomBar) {
                    if isResolving {
                        ProgressView()
                    } else {
                        Button { Task { await submitURL() } } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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
                    TextField("Enter post URL...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await submitURL() } }
                        .frame(width: 300)
                }
                ToolbarItem(placement: .principal) {
                    if isResolving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button { Task { await submitURL() } } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(settings: settings)
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
        let renderSize = archiver.renderSize
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

        archiver.enqueue(url: url)
        urlText = ""
    }
}
