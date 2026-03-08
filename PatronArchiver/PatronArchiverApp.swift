import PatronArchiverKit
import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var patronArchiver = PatronArchiver()

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
