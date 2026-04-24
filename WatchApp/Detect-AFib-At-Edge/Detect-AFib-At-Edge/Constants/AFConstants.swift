import Foundation

/// iOS-side mirror of the constants the companion needs for display.
/// Kept in sync manually with the watch app's `AFConstants`.
enum AFConstants {
    static let appGroupIdentifier: String = "group.EML-Labs.Detect-AFib-At-Edge"
    static let afProbabilityThreshold: Float = 0.5
    static let maxRetainedAlerts: Int = 30
    static let maxRetainedInferences: Int = 60
}
