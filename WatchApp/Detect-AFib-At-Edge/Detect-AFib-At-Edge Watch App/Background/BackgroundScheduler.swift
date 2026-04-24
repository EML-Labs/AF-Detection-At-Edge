import Foundation
import WatchKit

/// Schedules and handles `WKApplicationRefreshBackgroundTask` wakes for the
/// watch app. HealthKit observer queries already wake us when new beat
/// series arrive; this scheduler is a fallback that ensures we periodically
/// run a tick even on quiet stretches.
enum BackgroundScheduler {
    /// Schedule the next refresh `AFConstants.backgroundRefreshInterval`
    /// seconds out. Safe to call repeatedly.
    static func scheduleNext() {
        let preferredDate = Date().addingTimeInterval(AFConstants.backgroundRefreshInterval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error = error {
                NSLog("BackgroundScheduler scheduleBackgroundRefresh error: \(error.localizedDescription)")
            }
        }
    }

    /// Process a set of background tasks delivered by watchOS. Triggers a
    /// fetch tick, reschedules, and marks each task complete with
    /// snapshotting enabled so we can run again before the next refresh.
    @MainActor
    static func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let appRefresh as WKApplicationRefreshBackgroundTask:
                InferenceCoordinator.shared.runBackgroundTick()
                scheduleNext()
                appRefresh.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
