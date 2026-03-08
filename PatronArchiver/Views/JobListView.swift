import SwiftUI
import PatronArchiverKit

struct JobListView: View {
    var archiver: PatronArchiver

    var body: some View {
        List {
            ForEach(archiver.jobs) { job in
                JobRowView(job: job, archiver: archiver)
            }
        }
        .overlay {
            if archiver.jobs.isEmpty {
                ContentUnavailableView(
                    "No Jobs",
                    systemImage: "tray",
                    description: Text("Enter a URL to start archiving.")
                )
            }
        }
    }
}
