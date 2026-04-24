import SwiftUI

/// Top-level screen of the iOS companion app.
struct CompanionDashboardView: View {
    @EnvironmentObject private var session: PhoneSessionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatusCardView(status: session.status,
                                   lastInference: session.lastInference)

                    AlertHistoryView(alerts: session.recentAlerts,
                                     inferences: session.recentInferences)

                    troubleshootingCard
                }
                .padding(16)
            }
            .navigationTitle("Detect AFib")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.refreshFromAppGroup()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await session.requestHealthAuthorization()
                session.refreshFromAppGroup()
            }
        }
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Troubleshooting")
                .font(.headline)
            HStack {
                Image(systemName: session.isHealthAuthorized ? "checkmark.seal.fill" : "questionmark.circle")
                    .foregroundStyle(session.isHealthAuthorized ? .green : .orange)
                Text(session.isHealthAuthorized
                     ? "HealthKit access granted"
                     : "HealthKit access not confirmed")
                    .font(.callout)
            }
            HStack {
                Image(systemName: "applewatch")
                Text("Updates arrive when the watch records new beat-to-beat data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
