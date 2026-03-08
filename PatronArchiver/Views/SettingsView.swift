import SwiftUI
import UniformTypeIdentifiers
import WebKit
import PatronArchiverKit

struct SettingsView: View {
    @Bindable private var patronArchiver: PatronArchiver

    @State private var isPickingFolder = false
    @State private var loginEntry: SiteEntry?
    @State private var accountInfoByIdentifier: [String: AccountInfo] = [:]
    @State private var isCheckingLogin = false

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    private var siteEntries: [SiteEntry] {
        PatronServiceManager.allProviderTypes.map { providerType in
            SiteEntry(
                identifier: providerType.siteIdentifier,
                loginURL: providerType.loginURL,
                providerType: providerType
            )
        }
    }

    init(
        patronArchiver: PatronArchiver
    ) {
        self.patronArchiver = patronArchiver
    }

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(siteEntries) { entry in
                    HStack {
                        Label(entry.identifier, systemImage: "globe")
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
                    "Render Width: \(patronArchiver.settings.renderWidth)px",
                    value: $patronArchiver.settings.renderWidth,
                    in: 800...3840,
                    step: 160
                )

                HStack {
                    Text("Scroll Delay")
                    Spacer()
                    TextField("ms", value: $patronArchiver.settings.scrollDelay, format: .number)
                        .frame(width: 80)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Text("ms")
                }
            }

            Section("Metadata") {
                Toggle("Where Froms", isOn: $patronArchiver.settings.includesWhereFroms)
                Toggle("Finder Tags", isOn: $patronArchiver.settings.includesFinderTags)
            }

            Section("Storage") {
                HStack {
                    Text("Save Directory")
                    Spacer()
                    if let bookmark = patronArchiver.settings.savedDirectoryBookmark,
                       let url = try? {
                        var isStale = false
                        return try URL(
                            resolvingBookmarkData: bookmark,
                            options: Self.bookmarkResolutionOptions,
                            bookmarkDataIsStale: &isStale
                        )
                       }() {
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
                        patronArchiver.settings.savedDirectoryBookmark = try? url.bookmarkData(
                            options: Self.bookmarkCreationOptions,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    }
                }

                if patronArchiver.settings.savedDirectoryBookmark != nil {
                    Button("Reset to Default") {
                        patronArchiver.settings.savedDirectoryBookmark = nil
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
                    websiteDataStore: patronArchiver.websiteDataStore,
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

        let dataStore = patronArchiver.websiteDataStore
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
        let dataStore = patronArchiver.websiteDataStore
        let cookieStore = dataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()
        guard let host = entry.loginURL.host() else { return }

        for cookie in allCookies {
            let matches: Bool
            if cookie.domain.hasPrefix(".") {
                let domain = String(cookie.domain.dropFirst())
                matches = host == domain || host.hasSuffix("." + domain)
            } else {
                matches = host == cookie.domain
            }
            if matches {
                await cookieStore.deleteCookie(cookie)
            }
        }

        accountInfoByIdentifier.removeValue(forKey: entry.identifier)
    }

    private func checkLoginStatus(for providerType: any PatronServiceProvider.Type) async {
        let dataStore = patronArchiver.websiteDataStore
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
