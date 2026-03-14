import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(MessageUI)
import MessageUI
#endif
import SwiftUI

// MARK: - FeedbackMailComposer

struct FeedbackMailComposer {
    static let emailAddress = "PatronArchiver@sinoru.dev"
    static let subject = "PatronArchiver Feedback"

    static func diagnosticBody() -> String {
        let appVersion = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?[
            "CFBundleVersion"
        ] as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        #if os(macOS)
        let platform = "macOS"
        #elseif os(iOS)
        let platform = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPadOS" : "iOS"
        #else
        let platform = "Unknown"
        #endif

        return """

            ---
            App Version: \(appVersion) (\(buildNumber))
            Platform: \(platform)
            OS Version: \(osVersion)
            """
    }

    static var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: diagnosticBody()),
        ]
        return components.url
    }

    #if os(macOS)
    static func composeWithSharingService() {
        guard let service = NSSharingService(named: .composeEmail) else {
            if let url = mailtoURL {
                NSWorkspace.shared.open(url)
            }
            return
        }
        service.recipients = [emailAddress]
        service.subject = subject
        service.perform(withItems: [diagnosticBody()])
    }
    #endif
}

// MARK: - MailComposeView (iOS)

#if os(iOS)
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(
        context: Context
    ) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMailComposer.emailAddress])
        controller.setSubject(FeedbackMailComposer.subject)
        controller.setMessageBody(
            FeedbackMailComposer.diagnosticBody(),
            isHTML: false
        )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}
#endif
