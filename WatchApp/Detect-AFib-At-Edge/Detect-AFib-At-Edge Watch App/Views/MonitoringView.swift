import SwiftUI

/// Main watch screen showing the current monitoring state and the most
/// recent inference. Switches to a `WarningView` when the state machine
/// confirms an AF event.
struct MonitoringView: View {
    @ObservedObject var coordinator: InferenceCoordinator

    var body: some View {
        Group {
            if coordinator.status == .warning {
                WarningView(coordinator: coordinator)
            } else {
                idleOrMonitoringContent
            }
        }
        .onAppear {
            Task { await coordinator.bootstrap() }
        }
    }

    private var idleOrMonitoringContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(status: coordinator.status)

                if let inference = coordinator.lastInference {
                    inferenceSummary(inference)
                } else {
                    Text("Waiting for the watch to record beat-to-beat data. This typically happens during a workout or background heart-rate study.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !coordinator.isUsingBundledModel {
                    devModeBanner
                }

                if !coordinator.recentInferences.isEmpty {
                    Text("Recent windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(coordinator.recentInferences.suffix(6).reversed()) { record in
                        recentRow(record)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func inferenceSummary(_ inference: InferenceRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AF probability")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(percent(inference.probability))
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(inference.isPositive ? .red : .primary)
            Text("Window of \(inference.validSampleCount) RR samples · \(timeAgo(inference.timestamp))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func recentRow(_ record: InferenceRecord) -> some View {
        HStack {
            Circle()
                .fill(record.isPositive ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            Text(percent(record.probability))
                .font(.caption2)
                .monospacedDigit()
            Spacer()
            Text(timeAgo(record.timestamp))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var devModeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
            Text("Dev mode: bundled placeholder classifier")
                .font(.caption2)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.2))
        .foregroundStyle(.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func percent(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
