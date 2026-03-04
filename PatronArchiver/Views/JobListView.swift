import SwiftUI

struct JobListView: View {
    var archiver: PatronArchiver

    var body: some View {
        Group {
            if archiver.jobs.isEmpty {
                ContentUnavailableView(
                    "No Jobs",
                    systemImage: "tray",
                    description: Text("Enter a URL above to start archiving.")
                )
            } else {
                List {
                    ForEach(archiver.jobs) { job in
                        JobRowView(job: job, archiver: archiver)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
