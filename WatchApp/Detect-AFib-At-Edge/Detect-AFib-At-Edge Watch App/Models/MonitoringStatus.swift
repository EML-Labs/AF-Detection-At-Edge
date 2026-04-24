import Foundation

/// High-level state surfaced to the UI and mirrored to the iOS companion.
enum MonitoringStatus: String, Codable, Hashable {
    /// Permission not yet requested or denied; nothing happening.
    case idle
    /// Permission granted, waiting for HealthKit to deliver enough RR data
    /// to assemble the first model window.
    case collecting
    /// Inference is producing AF-negative or sub-threshold windows.
    case monitoring
    /// Recent windows lack enough valid RR intervals to make a confident call.
    case lowQuality
    /// Hysteresis-confirmed AF positive; user-facing warning is active.
    case warning
}
