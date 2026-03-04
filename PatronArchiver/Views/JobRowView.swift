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
                Text(job.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !job.status.isTerminal {
                    ProgressView(value: job.progress)
                }
            }
            Spacer()
            contextMenu
        }
        .padding(.vertical, 4)
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

    @ViewBuilder
    private var contextMenu: some View {
        Menu {
            if case .failed = job.status {
                Button("Retry") {
                    archiver.retryJob(job)
                }
            }
            if !job.status.isTerminal {
                Button("Cancel") {
                    archiver.cancelJob(job)
                }
            }
            Button("Remove", role: .destructive) {
                archiver.removeJob(job)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
    }
}
