import SwiftUI

/// Scrollable list of recent AFib alerts and recent inferences for
/// troubleshooting / clinical follow-up.
struct AlertHistoryView: View {
    let alerts: [AFAlert]
    let inferences: [InferenceRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent alerts")
                .font(.headline)
            if alerts.isEmpty {
                Text("No AFib alerts on record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.reversed()) { alert in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(format(alert.timestamp))
                                .font(.callout)
                            Text(String(format: "Confidence %.0f%%", alert.triggeringProbability * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Recent windows")
                .font(.headline)
            if inferences.isEmpty {
                Text("No inferences yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(inferences.suffix(10).reversed()) { record in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(record.isPositive ? Color.red : Color.green)
                            .frame(width: 10, height: 10)
                        Text(String(format: "%.0f%%", record.probability * 100))
                            .font(.callout)
                            .monospacedDigit()
                        Spacer()
                        Text(format(record.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
