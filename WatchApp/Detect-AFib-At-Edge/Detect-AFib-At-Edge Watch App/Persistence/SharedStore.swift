import Foundation
import HealthKit

/// Persistent storage backed by the shared App Group container.
///
/// Holds:
///   - HealthKit anchor for `HKAnchoredObjectQuery` so background wakes only
///     ingest new data.
///   - Window assembler state (rolling RR buffer + emission counter) so the
///     watch app survives termination without losing in-flight context.
///   - Warning state machine state.
///   - Last inference + recent inference history (for the UI / iOS companion).
///   - Recent AF alerts (for the iOS companion's history).
///   - Last warning timestamp (cooldown enforcement for notifications).
final class SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults
    private let anchorURL: URL?
    private let queue = DispatchQueue(label: "afib.shared.store", attributes: .concurrent)

    private enum Keys {
        static let assembler = "assembler.v1"
        static let stateMachine = "stateMachine.v1"
        static let lastInference = "lastInference.v1"
        static let recentInferences = "recentInferences.v1"
        static let recentAlerts = "recentAlerts.v1"
        static let lastWarningAt = "lastWarningAt.v1"
        static let monitoringStatus = "monitoringStatus.v1"
    }

    init(suiteName: String = AFConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            self.anchorURL = container.appendingPathComponent("hk.anchor")
        } else {
            self.anchorURL = nil
        }
    }

    // MARK: - HealthKit anchor

    func loadAnchor() -> HKQueryAnchor? {
        guard let url = anchorURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let url = anchorURL,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Assembler / state machine

    func loadAssembler() -> WindowAssembler {
        decode(Keys.assembler) ?? WindowAssembler()
    }

    func saveAssembler(_ assembler: WindowAssembler) {
        encode(assembler, key: Keys.assembler)
    }

    func loadStateMachine() -> WarningStateMachine {
        decode(Keys.stateMachine) ?? WarningStateMachine()
    }

    func saveStateMachine(_ machine: WarningStateMachine) {
        encode(machine, key: Keys.stateMachine)
    }

    // MARK: - UI-visible state

    func loadMonitoringStatus() -> MonitoringStatus {
        if let raw = defaults.string(forKey: Keys.monitoringStatus),
           let value = MonitoringStatus(rawValue: raw) {
            return value
        }
        return .idle
    }

    func saveMonitoringStatus(_ status: MonitoringStatus) {
        defaults.set(status.rawValue, forKey: Keys.monitoringStatus)
    }

    func loadLastInference() -> InferenceRecord? {
        decode(Keys.lastInference)
    }

    func loadRecentInferences() -> [InferenceRecord] {
        decode(Keys.recentInferences) ?? []
    }

    func appendInference(_ record: InferenceRecord) {
        queue.sync(flags: .barrier) {
            encode(record, key: Keys.lastInference)
            var history: [InferenceRecord] = decode(Keys.recentInferences) ?? []
            history.append(record)
            if history.count > AFConstants.maxRetainedInferences {
                history.removeFirst(history.count - AFConstants.maxRetainedInferences)
            }
            encode(history, key: Keys.recentInferences)
        }
    }

    func loadRecentAlerts() -> [AFAlert] {
        decode(Keys.recentAlerts) ?? []
    }

    func appendAlert(_ alert: AFAlert) {
        queue.sync(flags: .barrier) {
            var history: [AFAlert] = decode(Keys.recentAlerts) ?? []
            history.append(alert)
            if history.count > AFConstants.maxRetainedAlerts {
                history.removeFirst(history.count - AFConstants.maxRetainedAlerts)
            }
            encode(history, key: Keys.recentAlerts)
            defaults.set(alert.timestamp, forKey: Keys.lastWarningAt)
        }
    }

    func lastWarningTimestamp() -> Date? {
        defaults.object(forKey: Keys.lastWarningAt) as? Date
    }

    // MARK: - Codable helpers

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
