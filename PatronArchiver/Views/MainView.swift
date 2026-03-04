import SwiftUI

struct MainView: View {
    @State var archiver: PatronArchiver
    @State var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            URLInputView(archiver: archiver)
            Divider()
            JobListView(archiver: archiver)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}
