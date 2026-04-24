import Foundation

/// N-of-M hysteresis state machine that decides when to raise / clear an AF
/// warning. The thresholds, window length and required positive/negative
/// counts are read from `AFConstants`.
struct WarningStateMachine: Codable {
    enum Transition {
        case unchanged
        case raisedWarning
        case clearedWarning
    }

    private(set) var status: MonitoringStatus
    private var recentPositives: [Bool]

    init(status: MonitoringStatus = .idle, recentPositives: [Bool] = []) {
        self.status = status
        self.recentPositives = recentPositives
    }

    /// Update the machine with one fresh inference and return the resulting
    /// transition (used by the coordinator to decide whether to fire a
    /// notification).
    mutating func observe(_ record: InferenceRecord) -> Transition {
        recentPositives.append(record.isPositive)
        if recentPositives.count > AFConstants.hysteresisWindow {
            recentPositives.removeFirst(recentPositives.count - AFConstants.hysteresisWindow)
        }

        if record.validSampleCount < AFConstants.windowSize / 2 {
            if status != .warning {
                status = .lowQuality
            }
            return .unchanged
        }

        let positives = recentPositives.filter { $0 }.count
        let negatives = recentPositives.count - positives

        switch status {
        case .warning:
            if recentPositives.count >= AFConstants.hysteresisWindow,
               negatives >= AFConstants.negativesToClear {
                status = .monitoring
                return .clearedWarning
            }
            return .unchanged
        default:
            guard recentPositives.count >= AFConstants.hysteresisWindow else {
                status = .monitoring
                return .unchanged
            }
            if positives >= AFConstants.positivesToWarn {
                status = .warning
                return .raisedWarning
            }
            status = .monitoring
            return .unchanged
        }
    }

    /// External transition used when authorization changes or monitoring is
    /// stopped.
    mutating func setStatus(_ newStatus: MonitoringStatus) {
        status = newStatus
        if newStatus == .idle || newStatus == .collecting {
            recentPositives.removeAll(keepingCapacity: true)
        }
    }
}
