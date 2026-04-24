import Foundation

/// One AF classifier prediction over a single RR window.
struct InferenceRecord: Codable, Hashable, Identifiable {
    let id: UUID
    /// Timestamp at which the inference was produced (not the window's data).
    let timestamp: Date
    /// AF probability in [0, 1] returned by the Core ML classifier.
    let probability: Float
    /// True if the probability crossed the configured decision threshold.
    let isPositive: Bool
    /// Number of valid RR samples actually present in the scored window.
    /// Used by the state machine and UI to flag low-quality periods.
    let validSampleCount: Int
}
