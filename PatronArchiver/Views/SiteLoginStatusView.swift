import SwiftUI

struct SiteLoginStatusView: View {
    var settings: AppSettings
    @State private var loginURL: URL?

    private var siteEntries: [SiteEntry] {
        SitePluginRegistry.shared.allPluginTypes.map { pluginType in
            SiteEntry(identifier: pluginType.siteIdentifier, loginURL: pluginType.loginURL)
        }
    }

    var body: some View {
        List {
            Section("Sites") {
                ForEach(siteEntries) { entry in
                    Button {
                        loginURL = entry.loginURL
                    } label: {
                        Label(entry.identifier.capitalized, systemImage: "globe")
                    }
                }
            }
        }
        .navigationTitle("Login")
        .sheet(item: $loginURL) { url in
            NavigationStack {
                LoginWebView(url: url)
                    .navigationTitle("Login")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                loginURL = nil
                            }
                        }
                    }
            }
            #if os(macOS)
            .frame(width: 800, height: 600)
            #endif
        }
    }
}

private struct SiteEntry: Identifiable {
    let identifier: String
    let loginURL: URL
    var id: String { identifier }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
