import SwiftUI

/// Compact pill that summarizes the current monitoring state with colour and
/// icon. Used at the top of the main view.
struct StatusBadge: View {
    let status: MonitoringStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.2))
        )
        .overlay(
            Capsule().stroke(tint, lineWidth: 1)
        )
        .foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .idle: return "Idle"
        case .collecting: return "Collecting"
        case .monitoring: return "Monitoring"
        case .lowQuality: return "Low quality"
        case .warning: return "AF warning"
        }
    }

    private var iconName: String {
        switch status {
        case .idle: return "pause.circle"
        case .collecting: return "hourglass"
        case .monitoring: return "heart.text.square"
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
}
