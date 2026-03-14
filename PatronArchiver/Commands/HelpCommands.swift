import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif

struct HelpCommands: Commands {
    @Binding var showTipJarSheet: Bool
    #if os(iOS)
    @Binding var showMailCompose: Bool
    #endif

    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Send Feedback...") {
                #if os(macOS)
                FeedbackMailComposer.composeWithSharingService()
                #elseif canImport(MessageUI)
                if MFMailComposeViewController.canSendMail() {
                    showMailCompose = true
                } else if let url = FeedbackMailComposer.mailtoURL {
                    openURL(url)
                }
                #else
                if let url = FeedbackMailComposer.mailtoURL {
                    openURL(url)
                }
                #endif
            }

            Divider()

            Button("\(Text("Tip Jar"))...") {
                showTipJarSheet = true
            }
        }
    }
}
