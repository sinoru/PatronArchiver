import PatronArchiverKit
import SwiftUI

@main
struct PatronArchiverApp: App {
    #if DEBUG
    private static var isDemoMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoMode")
    }
    #endif

    @State
    private var transactionObserver = TransactionObserver()

    @State
    private var patronArchiver: PatronArchiver = {
        let archiver = PatronArchiver()
        #if DEBUG
        if isDemoMode {
            archiver.loadDemoJobs()
        }
        #endif
        return archiver
    }()

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
                #if os(macOS)
                #if DEBUG
                .frame(
                    minWidth: Self.isDemoMode ? 1440 : 635,
                    maxWidth: Self.isDemoMode ? 1440 : nil,
                    minHeight: Self.isDemoMode ? 900 : 400,
                    maxHeight: Self.isDemoMode ? 900 : nil
                )
                #else
                .frame(
                    minWidth: 635,
                    minHeight: 400
                )
                #endif
                #endif
        }
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
        #if DEBUG
        .defaultSize(
            width: Self.isDemoMode ? 1440 : 635,
            height: Self.isDemoMode ? 900 : 400
        )
        .defaultPosition(Self.isDemoMode ? .topLeading : .center)
        #else
        .defaultSize(
            width: 635,
            height: 400
        )
        #endif
        #endif

        #if os(macOS)
        Settings {
            SettingsView(patronArchiver: patronArchiver)
        }
        #endif
    }
}
