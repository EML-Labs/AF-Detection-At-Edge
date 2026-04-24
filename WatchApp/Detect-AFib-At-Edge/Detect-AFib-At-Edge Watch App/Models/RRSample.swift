import Foundation

/// One inter-beat interval emitted by `HKHeartbeatSeriesQuery`.
struct RRSample: Codable, Hashable {
    /// RR interval in milliseconds.
    let intervalMs: Double
    /// Approximate timestamp at which the beat that closed this interval occurred.
    let timestamp: Date
    /// True when HealthKit reported a gap immediately before this beat
    /// (`HKHeartbeatSeriesQuery` `precededByGap` flag). Such samples are
    /// dropped during quality control.
    let precededByGap: Bool
}
