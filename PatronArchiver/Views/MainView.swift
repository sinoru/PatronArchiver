import SwiftUI

struct MainView: View {
    @State var jobEngine: JobEngine
    @State var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            SiteLoginStatusView(settings: settings)
        } detail: {
            VStack(spacing: 0) {
                URLInputView(jobEngine: jobEngine)
                Divider()
                JobListView(jobEngine: jobEngine)
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }
}
