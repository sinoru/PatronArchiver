import SwiftUI

struct JobRowView: View {
    var job: ArchiveJob
    var archiver: PatronArchiver

    var body: some View {
        HStack {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(job.metadata?.title ?? job.inputURL.absoluteString)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let metadata = job.metadata {
                        Text(metadata.authorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(job.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !job.status.isTerminal {
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
        default:
            ProgressView()
                #if os(macOS)
                .controlSize(.small)
                #endif
        }
    }
}
