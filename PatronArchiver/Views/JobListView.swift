import SwiftUI

struct JobListView: View {
    var jobEngine: JobEngine

    var body: some View {
        Group {
            if jobEngine.jobs.isEmpty {
                ContentUnavailableView(
                    "No Jobs",
                    systemImage: "tray",
                    description: Text("Enter a URL above to start archiving.")
                )
            } else {
                List {
                    ForEach(jobEngine.jobs) { job in
                        JobRowView(job: job, jobEngine: jobEngine)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
