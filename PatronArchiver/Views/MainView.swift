import SwiftUI

struct MainView: View {
    @State var archiver: PatronArchiver
    @State var settings: AppSettings
    @State private var urlText = ""
    #if os(iOS)
    @State private var showSettings = false
    #endif

    var body: some View {
        NavigationStack {
            JobListView(archiver: archiver)
                .navigationTitle("PatronArchiver")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        TextField("Enter post URL...", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .onSubmit { submitURL() }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button { submitURL() } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                    #else
                    ToolbarItem(placement: .principal) {
                        TextField("Enter post URL...", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submitURL() }
                            .frame(width: 300)
                    }
                    ToolbarItem(placement: .principal) {
                        Button { submitURL() } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    #endif
                }
                #if os(iOS)
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(settings: settings)
                            .navigationTitle("Settings")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        showSettings = false
                                    }
                                }
                            }
                    }
                }
                #endif
                #if os(macOS)
                .frame(minWidth: 635, minHeight: 400)
                #endif
        }
    }

    private func submitURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            let urlString = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlString), url.scheme != nil else { continue }
            archiver.enqueue(url: url)
        }
        urlText = ""
    }
}
