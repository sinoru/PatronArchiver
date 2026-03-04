import SwiftUI

@main
struct PatronArchiverApp: App {
    @State private var settings = AppSettings()
    @State private var jobEngine: JobEngine?

    var body: some Scene {
        WindowGroup {
            if let jobEngine {
                MainView(jobEngine: jobEngine, settings: settings)
            } else {
                ProgressView()
                    .task {
                        jobEngine = JobEngine(settings: settings)
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
