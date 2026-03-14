import PatronArchiverKit
import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var patronArchiver: PatronArchiver = {
        let archiver = PatronArchiver()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoMode") {
            archiver.loadDemoJobs()
        }
        #endif
        return archiver
    }()

    var body: some Scene {
        WindowGroup {
            MainView(patronArchiver: patronArchiver)
        }

        #if os(macOS)
        Settings {
            SettingsView(patronArchiver: patronArchiver)
        }
        #endif
    }
}
