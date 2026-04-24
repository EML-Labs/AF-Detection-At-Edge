import Foundation

/// Read-only iOS view of the App Group store written by the watch app.
final class SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults

    private enum Keys {
        static let lastInference = "lastInference.v1"
        static let recentInferences = "recentInferences.v1"
        static let recentAlerts = "recentAlerts.v1"
        static let monitoringStatus = "monitoringStatus.v1"
    }

    init(suiteName: String = AFConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func loadMonitoringStatus() -> MonitoringStatus {
        if let raw = defaults.string(forKey: Keys.monitoringStatus),
           let value = MonitoringStatus(rawValue: raw) {
            return value
        }
        return .idle
    }

    func loadLastInference() -> InferenceRecord? {
        decode(Keys.lastInference)
    }

    func loadRecentInferences() -> [InferenceRecord] {
        decode(Keys.recentInferences) ?? []
    }

    func loadRecentAlerts() -> [AFAlert] {
        decode(Keys.recentAlerts) ?? []
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
