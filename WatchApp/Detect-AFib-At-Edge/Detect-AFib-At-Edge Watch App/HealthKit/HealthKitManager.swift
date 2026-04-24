import Foundation
import HealthKit

/// Owns the shared `HKHealthStore` and authorization flow for the watch app.
///
/// Authorization is requested for the heart-beat-series type only; everything
/// else this app does is on-device inference and does not require additional
/// HealthKit reads/writes.
final class HealthKitManager {
    static let shared = HealthKitManager()

    let healthStore = HKHealthStore()

    private init() {}

    /// True when HealthKit is usable on this device. iOS Simulators and some
    /// devices may not support beat-to-beat data.
    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The single HealthKit type we read.
    var heartbeatSeriesType: HKSeriesType { HKSeriesType.heartbeat() }

    /// Current authorization status for reading heart-beat series.
    /// Note: HealthKit deliberately reports `.sharingDenied` rather than
    /// `.notDetermined` for read-only types after the prompt to protect
    /// privacy, so absence of authorization should be treated as "unknown".
    var authorizationStatus: HKAuthorizationStatus {
        healthStore.authorizationStatus(for: heartbeatSeriesType)
    }

    /// Request read access to heart-beat series. Safe to call repeatedly;
    /// the system only prompts once.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { return }
        try await healthStore.requestAuthorization(toShare: [], read: [heartbeatSeriesType])
    }
}
