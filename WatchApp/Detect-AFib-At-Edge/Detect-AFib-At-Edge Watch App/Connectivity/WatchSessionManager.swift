import Foundation
import WatchConnectivity

/// Mirrors the latest monitoring snapshot to the iOS companion using
/// `WCSession.updateApplicationContext`, which is best-effort but persists
/// the most recent value across restarts (perfect for "current status").
///
/// The companion app reads this in addition to the App Group store.
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Push the current snapshot of monitoring state to the iPhone.
    func sendSnapshot(status: MonitoringStatus,
                      lastInference: InferenceRecord?,
                      latestAlert: AFAlert?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var payload: [String: Any] = ["status": status.rawValue]
        if let inference = lastInference,
           let data = try? JSONEncoder().encode(inference) {
            payload["lastInference"] = data
        }
        if let alert = latestAlert,
           let data = try? JSONEncoder().encode(alert) {
            payload["latestAlert"] = data
        }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            NSLog("WatchSessionManager updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error = error {
            NSLog("WCSession activation error: \(error.localizedDescription)")
        }
    }
}
