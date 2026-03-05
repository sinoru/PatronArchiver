import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var isPickingFolder = false
    @State private var loginEntry: SiteEntry?
    @State private var accountInfoByIdentifier: [String: AccountInfo] = [:]
    @State private var isCheckingLogin = false

    private var siteEntries: [SiteEntry] {
        PatronServiceManager.allProviderTypes.map { providerType in
            SiteEntry(
                identifier: providerType.siteIdentifier,
                loginURL: providerType.loginURL,
                providerType: providerType
            )
        }
    }

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(siteEntries) { entry in
                    HStack {
                        Label(entry.identifier.capitalized, systemImage: "globe")
                        Spacer()
                        if isCheckingLogin {
                            ProgressView()
                                #if os(macOS)
                                .controlSize(.small)
                                #endif
                        } else if let info = accountInfoByIdentifier[entry.identifier] {
                            Text(info.displayName)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not logged in")
                                .foregroundStyle(.tertiary)
                        }
                        if accountInfoByIdentifier[entry.identifier] != nil {
                            Button("Logout") {
                                Task {
                                    await logout(for: entry)
                                }
                            }
                        } else {
                            Button("Login") {
                                loginEntry = entry
                            }
                        }
                    }
                }
            }

            Section("Rendering") {
                Stepper(
                    "Render Width: \(settings.renderWidth)px",
                    value: $settings.renderWidth,
                    in: 800...3840,
                    step: 160
                )

                HStack {
                    Text("Scroll Delay")
                    Spacer()
                    TextField("ms", value: $settings.scrollDelay, format: .number)
                        .frame(width: 80)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Text("ms")
                }
            }

            Section("Processing") {
                Stepper(
                    "Max Concurrent Jobs: \(settings.maxConcurrentJobs)",
                    value: $settings.maxConcurrentJobs,
                    in: 1...10
                )
            }

            Section("Storage") {
                HStack {
                    Text("Save Directory")
                    Spacer()
                    if let bookmark = settings.savedDirectoryBookmark,
                       let url = try? BookmarkManager.resolveBookmark(bookmark) {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Default")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Choose Folder...") {
                    isPickingFolder = true
                }
                .fileImporter(
                    isPresented: $isPickingFolder,
                    allowedContentTypes: [.folder]
                ) { result in
                    if case .success(let url) = result {
                        settings.savedDirectoryBookmark = try? BookmarkManager.saveBookmark(for: url)
                    }
                }

                if settings.savedDirectoryBookmark != nil {
                    Button("Reset to Default") {
                        settings.savedDirectoryBookmark = nil
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 450)
        .padding()
        #endif
        .task {
            await checkAllLoginStatus()
        }
        .sheet(item: $loginEntry) { entry in
            NavigationStack {
                LoginWebView(
                    url: entry.loginURL,
                    providerType: entry.providerType,
                    onLoginDetected: {
                        loginEntry = nil
                    }
                )
                .navigationTitle("Login")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            loginEntry = nil
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(width: 800, height: 600)
            #endif
        }
        .onChange(of: loginEntry) { oldValue, newValue in
            if newValue == nil, let closedEntry = oldValue {
                Task {
                    // Brief delay to allow cookies to propagate
                    try? await Task.sleep(for: .milliseconds(500))
                    await checkLoginStatus(for: closedEntry.providerType)
                }
            }
        }
    }

    private func checkAllLoginStatus() async {
        isCheckingLogin = true
        defer { isCheckingLogin = false }

        let dataStore = WKWebsiteDataStore.default()
        let providerTypes = PatronServiceManager.allProviderTypes

        await withTaskGroup(of: (String, AccountInfo?).self) { group in
            for providerType in providerTypes {
                let identifier = providerType.siteIdentifier
                group.addTask {
                    let info = await LoginChecker.check(for: providerType, dataStore: dataStore)
                    return (identifier, info)
                }
            }
            for await (identifier, info) in group {
                if let info {
                    accountInfoByIdentifier[identifier] = info
                } else {
                    accountInfoByIdentifier.removeValue(forKey: identifier)
                }
            }
        }
    }

    private func logout(for entry: SiteEntry) async {
        let dataStore = WKWebsiteDataStore.default()
        let cookieStore = dataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()
        guard let host = entry.loginURL.host() else { return }

        for cookie in allCookies {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            if host.hasSuffix(domain) {
                await cookieStore.deleteCookie(cookie)
            }
        }

        accountInfoByIdentifier.removeValue(forKey: entry.identifier)
    }

    private func checkLoginStatus(for providerType: any PatronServiceProvider.Type) async {
        let dataStore = WKWebsiteDataStore.default()
        let info = await LoginChecker.check(for: providerType, dataStore: dataStore)
        if let info {
            accountInfoByIdentifier[providerType.siteIdentifier] = info
        } else {
            accountInfoByIdentifier.removeValue(forKey: providerType.siteIdentifier)
        }
    }
}

private struct SiteEntry: Identifiable, Equatable {
    let identifier: String
    let loginURL: URL
    let providerType: any PatronServiceProvider.Type
    var id: String { identifier }

    static func == (lhs: SiteEntry, rhs: SiteEntry) -> Bool {
        lhs.identifier == rhs.identifier
    }
}
