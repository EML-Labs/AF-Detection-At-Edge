import SwiftUI
import WatchKit

/// Full-screen warning surface shown when the state machine confirms AF.
/// Includes haptic feedback and explicit guidance.
struct WarningView: View {
    @ObservedObject var coordinator: InferenceCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.red)

                Text("Possible AFib")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let inference = coordinator.lastInference {
                    Text(String(format: "Confidence %.0f%%", inference.probability * 100))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }

                Text("Your recent heart rhythm looks irregular. This is not a diagnosis. If you feel unwell, contact a clinician.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
        .onAppear {
            WKInterfaceDevice.current().play(.notification)
        }
    }
}
