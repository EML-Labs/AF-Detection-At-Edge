import Foundation
import UserNotifications

/// Fires watchOS local notifications for AF warnings, applying the
/// `warningCooldown` so a flapping state machine does not spam the user.
final class AFNotifier {
    static let shared = AFNotifier()

    private let center = UNUserNotificationCenter.current()
    private let store: SharedStore

    init(store: SharedStore = .shared) {
        self.store = store
    }

    /// Request notification permission. Safe to call repeatedly.
    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("AFNotifier authorization error: \(error.localizedDescription)")
        }
    }

    /// Schedule an immediate AF warning notification, honouring the cooldown.
    func notifyAFDetected(probability: Float) {
        if let last = store.lastWarningTimestamp(),
           Date().timeIntervalSince(last) < AFConstants.warningCooldown {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Possible AFib detected"
        content.body = String(
            format: "Recent heart rhythm looks irregular (confidence %.0f%%). Tap for details.",
            probability * 100
        )
        content.sound = .defaultCritical
        let request = UNNotificationRequest(
            identifier: "afib.warning.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error = error {
                NSLog("AFNotifier add notification error: \(error.localizedDescription)")
            }
        }
    }
}
