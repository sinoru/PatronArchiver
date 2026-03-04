import SwiftUI

struct URLInputView: View {
    var jobEngine: JobEngine
    @State private var urlText = ""

    var body: some View {
        HStack {
            TextField("Enter post URL...", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitURL() }
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Button("Archive") {
                submitURL()
            }
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    private func submitURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Support multiple URLs separated by newlines
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            let urlString = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlString), url.scheme != nil else { continue }
            jobEngine.enqueue(url: url)
        }
        urlText = ""
    }
}
