import Foundation

/// Configuration locked by the model contract from Part 1.
///
/// Window length, stride, RobustScaler parameters and the decision threshold are
/// hardcoded here for the initial validation phase as agreed in the plan.
/// All runtime modules (window assembler, scaler, warning state machine) read
/// from this single source of truth.
enum AFConstants {
    /// Number of RR intervals fed to the model per window.
    static let windowSize: Int = 200

    /// Number of new RR intervals between consecutive windows (sliding step).
    static let stride: Int = 50

    /// Physiological bounds used by the RR quality filter (milliseconds).
    static let minValidRRMs: Double = 200
    static let maxValidRRMs: Double = 2000

    /// Maximum number of RR intervals retained in the rolling buffer.
    /// Keeps roughly one window of history beyond the active window so older
    /// data is dropped without losing in-flight context.
    static let bufferCapacity: Int = windowSize * 4

    /// Bound the amount of inference work performed in a single background wake.
    /// Inference is cheap on Apple Silicon NPU but background budgets are tight,
    /// so we cap the number of windows processed per task.
    static let maxWindowsPerWake: Int = 4

    /// AF probability threshold above which a window is considered positive.
    /// Final tuned value comes from Part 1 but a conservative default is set
    /// here so the state machine can be exercised end-to-end.
    static let afProbabilityThreshold: Float = 0.5

    /// Hysteresis: require `positivesToWarn` of the last `hysteresisWindow`
    /// inferences to be positive to raise a warning, and `negativesToClear`
    /// of the last `hysteresisWindow` to clear it.
    static let hysteresisWindow: Int = 5
    static let positivesToWarn: Int = 3
    static let negativesToClear: Int = 4

    /// How often we proactively schedule a background refresh on top of any
    /// HealthKit-driven wakes.
    static let backgroundRefreshInterval: TimeInterval = 15 * 60

    /// Minimum time between repeat AF warning notifications. Prevents spam
    /// when the state machine flaps near the threshold.
    static let warningCooldown: TimeInterval = 10 * 60

    /// Maximum number of inference records and alerts retained in shared storage
    /// for the iOS companion to display.
    static let maxRetainedInferences: Int = 60
    static let maxRetainedAlerts: Int = 30

    /// Identifier of the shared App Group container used to mirror state
    /// between the watch app and iOS companion.
    static let appGroupIdentifier: String = "group.EML-Labs.Detect-AFib-At-Edge"

    /// RobustScaler parameters captured from the patient-specific scaler used
    /// during training. Hardcoded for testing; replace per the plan once the
    /// production scaler ships from Part 1.
    enum RobustScalerParams {
        /// Median of the patient's RR intervals (milliseconds).
        static let median: Float = 800.0
        /// Inter-quartile-range-derived scale used by sklearn's RobustScaler.
        /// Stored as the divisor applied as `(rr - median) / scale`.
        static let scale: Float = 120.0
    }
}
