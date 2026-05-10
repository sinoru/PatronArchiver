import PatronArchiverKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if canImport(MessageUI)
import MessageUI
#endif

struct SettingsView: View {
    @Bindable private var patronArchiver: PatronArchiver

    @State private var verificationWebViews: [String: WKWebView] = [:]
    @State private var isPickingFolder = false
    @State private var loginEntry: SiteEntry?
    @State private var accountStatuses: [String: AccountStatus] = [:]

    #if os(iOS)
    @Environment(\.openURL) private var openURL
    @State private var showMailCompose = false
    #endif

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

    @ViewBuilder
    private var verificationWebViewArea: some View {
        let renderSize = patronArchiver.renderSize

        ZStack {
            ForEach(verificationWebViews.keys.sorted(), id: \.self) { identifier in
                if let webView = verificationWebViews[identifier] {
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
            }
        }
    }

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(siteEntries) { entry in
                    let status = accountStatuses[entry.identifier] ?? .unknown
                    HStack {
                        Label(entry.identifier, systemImage: "globe")
                        Spacer()
                        switch status {
                        case .unknown, .verifying:
                            ProgressView()
                                #if os(macOS)
                                .controlSize(.small)
                                #endif
                        case .notSignedIn:
                            Text("Not signed in")
                                .foregroundStyle(.tertiary)
                        case .verified(let info):
                            Text(info.displayName)
                                .foregroundStyle(.secondary)
                        case .verificationFailed:
                            Text("Verification failed")
                                .foregroundStyle(.red)
                        }
                        switch status {
                        case .notSignedIn:
                            Button("Sign In") {
                                loginEntry = entry
                            }
                        case .verified, .verificationFailed, .verifying:
                            Button("Sign Out") {
                                Task {
                                    await logout(for: entry)
                                }
                            }
                        case .unknown:
                            EmptyView()
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
                Toggle("Content Dates", isOn: $patronArchiver.settings.includesContentDates)
            }

            Section("Storage") {
                HStack {
                    Text("Save Location")
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

            #if os(iOS)
            Section("Support") {
                TipJarView()
            }

            Section("Feedback") {
                Button("Send Feedback...") {
                    if MFMailComposeViewController.canSendMail() {
                        showMailCompose = true
                    } else if let url = FeedbackMailComposer.mailtoURL {
                        openURL(url)
                    }
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .background {
            verificationWebViewArea
        }
        #if os(macOS)
        .frame(width: 450)
        .padding()
        #endif
        .task {
            await checkAllLoginStatus()
        }
        .onDisappear {
            for status in accountStatuses.values {
                if case .verifying(let task) = status {
                    task.cancel()
                }
            }
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
                .navigationTitle("Sign In")
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
        #if os(iOS)
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
        #endif
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
        let providerTypes = PatronServiceManager.allProviderTypes

        // 1. Fast cookie-based login check (concurrent)
        await withTaskGroup(of: (String, Bool).self) { group in
            for providerType in providerTypes {
                let identifier = providerType.siteIdentifier
                group.addTask {
                    let loggedIn = await patronArchiver.isLoggedIn(for: providerType)
                    return (identifier, loggedIn)
                }
            }
            for await (identifier, loggedIn) in group {
                if !loggedIn {
                    accountStatuses[identifier] = .notSignedIn
                }
            }
        }

        // 2. Verify logged-in providers (concurrent, fresh WKWebView per provider).
        for providerType in providerTypes {
            let identifier = providerType.siteIdentifier
            if case .notSignedIn = accountStatuses[identifier] ?? .unknown { continue }
            verify(providerType)
        }
    }

    private func verify(_ providerType: any PatronServiceProviding.Type) {
        let identifier = providerType.siteIdentifier

        if case .verifying(let oldTask) = accountStatuses[identifier] {
            oldTask.cancel()
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = patronArchiver.websiteDataStore
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: patronArchiver.renderSize),
            configuration: configuration
        )
        verificationWebViews[identifier] = webView

        let task = Task {
            defer {
                if verificationWebViews[identifier] === webView {
                    verificationWebViews[identifier] = nil
                }
            }

            // WKWebView only renders when attached to the window — wait for layout.
            // `window` is flagged unsafe under strict memory safety; reading it on the main actor is fine.
            for _ in 0..<100 {
                if unsafe webView.window != nil { break }
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }

            let info = await patronArchiver.fetchAccountInfo(
                for: providerType,
                in: webView
            )
            if !Task.isCancelled {
                accountStatuses[identifier] = info.map(AccountStatus.verified) ?? .verificationFailed
            }
        }
        accountStatuses[identifier] = .verifying(task)
    }

    private func logout(for entry: SiteEntry) async {
        if case .verifying(let task) = accountStatuses[entry.identifier] {
            task.cancel()
        }

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

        accountStatuses[entry.identifier] = .notSignedIn
    }

    private func checkLoginStatus(for providerType: any PatronServiceProviding.Type) async {
        let identifier = providerType.siteIdentifier

        let loggedIn = await patronArchiver.isLoggedIn(for: providerType)
        guard loggedIn else {
            if case .verifying(let task) = accountStatuses[identifier] {
                task.cancel()
            }
            accountStatuses[identifier] = .notSignedIn
            return
        }

        verify(providerType)
    }
}

private struct SiteEntry: Identifiable, Equatable {
    let identifier: String
    let loginURL: URL
    let providerType: any PatronServiceProviding.Type
    var id: String { identifier }

    static func == (lhs: SiteEntry, rhs: SiteEntry) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

private enum AccountStatus {
    case unknown
    case notSignedIn
    case verifying(Task<Void, Never>)
    case verified(AccountInfo)
    case verificationFailed
}
