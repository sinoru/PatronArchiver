import PatronArchiverKit
import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var transactionObserver = TransactionObserver()

    @State private var patronArchiver: PatronArchiver = {
        let archiver = PatronArchiver()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoMode") {
            archiver.loadDemoJobs()
        }
        #endif
        return archiver
    }()

    #if DEBUG
    private let isDemoMode = ProcessInfo.processInfo.arguments.contains("-DemoMode")
    #endif

    @State private var showTipJarSheet = false
    #if os(iOS)
    @State private var showMailCompose = false
    #endif

    var body: some Scene {
        WindowGroup {
            MainView(patronArchiver: patronArchiver)
                .sheet(isPresented: $showTipJarSheet) {
                    TipJarSheet()
                }
                #if os(iOS)
                .sheet(isPresented: $showMailCompose) {
                    MailComposeView()
                }
                #endif
        }
        #if DEBUG
        .defaultSize(
            width: isDemoMode ? 1440 : 635,
            height: isDemoMode ? 900 : 400
        )
        #endif
        .commands {
            #if os(iOS)
            HelpCommands(
                showTipJarSheet: $showTipJarSheet,
                showMailCompose: $showMailCompose
            )
            #else
            HelpCommands(showTipJarSheet: $showTipJarSheet)
            #endif
        }

        #if os(macOS)
        Settings {
            SettingsView(patronArchiver: patronArchiver)
        }
        #endif
    }
}
