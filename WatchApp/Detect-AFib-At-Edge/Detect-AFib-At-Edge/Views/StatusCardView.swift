import SwiftUI

/// Top card on the iOS companion screen summarizing the current monitoring
/// state and the most recent inference, mirroring the watch UI's badge.
struct StatusCardView: View {
    let status: MonitoringStatus
    let lastInference: InferenceRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                Spacer()
            }
            Divider()
            if let inference = lastInference {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AF probability")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%", inference.probability * 100))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(inference.isPositive ? .red : .primary)
                    Text("Last update \(formatted(inference.timestamp)) · window of \(inference.validSampleCount) RR samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No inferences yet. Wear the watch and let it record beat-to-beat data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var label: String {
        switch status {
        case .idle: return "Idle"
        case .collecting: return "Collecting data"
        case .monitoring: return "Monitoring"
        case .lowQuality: return "Low signal quality"
        case .warning: return "AFib warning active"
        }
    }

    private var iconName: String {
        switch status {
        case .idle: return "pause.circle"
        case .collecting: return "hourglass"
        case .monitoring: return "heart.text.square.fill"
        case .lowQuality: return "antenna.radiowaves.left.and.right.slash"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: return .gray
        case .collecting: return .blue
        case .monitoring: return .green
        case .lowQuality: return .yellow
        case .warning: return .red
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
