import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var isPickingFolder = false

    var body: some View {
        Form {
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
    }
}
