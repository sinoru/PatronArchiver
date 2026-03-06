import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainView(settings: settings)
        }

        #if os(macOS)
        Settings {
            SettingsView(settings: settings)
        }
        #endif
    }
}
