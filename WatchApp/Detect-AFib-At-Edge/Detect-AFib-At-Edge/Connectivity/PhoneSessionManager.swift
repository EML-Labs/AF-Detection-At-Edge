import Foundation
import HealthKit
import WatchConnectivity

/// Receives the watch's monitoring snapshots via `WCSession` and exposes them
/// to SwiftUI through `@Published` properties. Falls back to the App Group
/// store on launch so values survive a reboot of the iOS app while the
/// watch app is asleep.
@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var status: MonitoringStatus
    @Published var lastInference: InferenceRecord?
    @Published var lastAlert: AFAlert?
    @Published var recentInferences: [InferenceRecord]
    @Published var recentAlerts: [AFAlert]
    @Published var isHealthAuthorized: Bool = false

    private let store: SharedStore
    private let healthStore = HKHealthStore()

    override init() {
        self.store = .shared
        self.status = SharedStore.shared.loadMonitoringStatus()
        self.lastInference = SharedStore.shared.loadLastInference()
        let alerts = SharedStore.shared.loadRecentAlerts()
        self.lastAlert = alerts.last
        self.recentInferences = SharedStore.shared.loadRecentInferences()
        self.recentAlerts = alerts
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func refreshFromAppGroup() {
        status = store.loadMonitoringStatus()
        lastInference = store.loadLastInference()
        recentInferences = store.loadRecentInferences()
        let alerts = store.loadRecentAlerts()
        recentAlerts = alerts
        lastAlert = alerts.last
    }

    func requestHealthAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [HKSeriesType.heartbeat()])
            isHealthAuthorized = true
        } catch {
            isHealthAuthorized = false
            NSLog("PhoneSessionManager HealthKit auth error: \(error.localizedDescription)")
        }
    }

    fileprivate func apply(applicationContext: [String: Any]) {
        if let raw = applicationContext["status"] as? String,
           let value = MonitoringStatus(rawValue: raw) {
            status = value
        }
        if let data = applicationContext["lastInference"] as? Data,
           let record = try? JSONDecoder().decode(InferenceRecord.self, from: data) {
            lastInference = record
            recentInferences.append(record)
            if recentInferences.count > AFConstants.maxRetainedInferences {
                recentInferences.removeFirst(recentInferences.count - AFConstants.maxRetainedInferences)
            }
        }
        if let data = applicationContext["latestAlert"] as? Data,
           let alert = try? JSONDecoder().decode(AFAlert.self, from: data) {
            if lastAlert?.id != alert.id {
                lastAlert = alert
                recentAlerts.append(alert)
                if recentAlerts.count > AFConstants.maxRetainedAlerts {
                    recentAlerts.removeFirst(recentAlerts.count - AFConstants.maxRetainedAlerts)
                }
            }
        }
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let error = error {
            NSLog("WCSession activation error: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext: applicationContext)
        }
    }
}
