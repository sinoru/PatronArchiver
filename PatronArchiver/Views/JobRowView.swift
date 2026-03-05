import SwiftUI

struct JobRowView: View {
    var job: ArchiveJob
    var archiver: PatronArchiver

    var body: some View {
        HStack {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(jobTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(job.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .awaitingOverwriteConfirmation = job.status {
                    HStack(spacing: 8) {
                        Button("Overwrite") {
                            archiver.confirmOverwrite(job)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        Button("Skip") {
                            archiver.skipOverwrite(job)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if !job.status.isTerminal {
                    ProgressView(value: job.progress)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                archiver.removeJob(job)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            if !job.status.isTerminal {
                Button {
                    archiver.cancelJob(job)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if case .failed = job.status {
                Button {
                    archiver.retryJob(job)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if case .awaitingOverwriteConfirmation = job.status {
                Button {
                    archiver.confirmOverwrite(job)
                } label: {
                    Label("Overwrite", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    archiver.skipOverwrite(job)
                } label: {
                    Label("Skip", systemImage: "forward")
                }
            }
            if case .failed = job.status {
                Button {
                    archiver.retryJob(job)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
            if !job.status.isTerminal {
                Button {
                    archiver.cancelJob(job)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }
            Button(role: .destructive) {
                archiver.removeJob(job)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var jobTitle: String {
        if let metadata = job.metadata {
            return "\(metadata.siteIdentifier.capitalized) - \(metadata.authorName) - \(metadata.title) (\(metadata.postID))"
        }
        return job.inputURL.absoluteString
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .awaitingOverwriteConfirmation:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            ProgressView()
                #if os(macOS)
                .controlSize(.small)
                #endif
        }
    }
}
