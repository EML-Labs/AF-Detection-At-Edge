import Foundation

/// Persisted record of a user-facing AF warning event.
struct AFAlert: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    /// Probability of the inference that triggered the warning state.
    let triggeringProbability: Float
}
