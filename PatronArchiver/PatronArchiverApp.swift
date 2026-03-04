import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var settings = AppSettings()
    @State private var archiver: PatronArchiver?

    var body: some Scene {
        WindowGroup {
            if let archiver {
                MainView(archiver: archiver, settings: settings)
            } else {
                ProgressView()
                    .task {
                        archiver = PatronArchiver(settings: settings)
                    }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(settings: settings)
        }
        #endif
    }
}
