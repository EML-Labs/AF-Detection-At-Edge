import Foundation
import Combine

/// Top-level orchestrator that wires together:
///   - HealthKit `HeartbeatSeriesIngestor`
///   - RR quality filter
///   - persistent `WindowAssembler`
///   - `AFClassifier` Core ML inference
///   - `WarningStateMachine` and notifications
///   - mirroring to the iOS companion via `WatchSessionManager`
///
/// All mutating work runs on a private serial queue so background-wake and
/// foreground callbacks do not race on the buffer / state machine.
@MainActor
final class InferenceCoordinator: ObservableObject {
    static let shared = InferenceCoordinator()

    @Published private(set) var status: MonitoringStatus = .idle
    @Published private(set) var lastInference: InferenceRecord?
    @Published private(set) var recentInferences: [InferenceRecord] = []
    @Published private(set) var isUsingBundledModel: Bool = false
    @Published private(set) var authorizationRequested: Bool = false

    private let store: SharedStore
    private let ingestor: HeartbeatSeriesIngestor
    private let classifier: AFClassifier
    private let notifier: AFNotifier
    private let workQueue = DispatchQueue(label: "afib.inference.coordinator")

    private var assembler: WindowAssembler
    private var stateMachine: WarningStateMachine

    init(store: SharedStore = .shared,
         ingestor: HeartbeatSeriesIngestor = HeartbeatSeriesIngestor(),
         classifier: AFClassifier = AFClassifier(),
         notifier: AFNotifier = .shared) {
        self.store = store
        self.ingestor = ingestor
        self.classifier = classifier
        self.notifier = notifier
        self.assembler = store.loadAssembler()
        self.stateMachine = store.loadStateMachine()
        self.status = store.loadMonitoringStatus()
        self.lastInference = store.loadLastInference()
        self.recentInferences = store.loadRecentInferences()
        self.isUsingBundledModel = classifier.isUsingBundledModel
    }

    /// Request HealthKit + notification authorization and start ingesting RR
    /// data. Idempotent.
    func bootstrap() async {
        authorizationRequested = true
        do {
            try await HealthKitManager.shared.requestAuthorization()
        } catch {
            NSLog("HealthKit authorization failed: \(error.localizedDescription)")
        }
        await notifier.requestAuthorization()

        ingestor.start { [weak self] batch in
            self?.handleNewRRBatch(batch)
        }

        if status == .idle {
            updateStatus(.collecting)
        }
        ingestor.fetchOnDemand()
    }

    /// Called by the background task handler to run any pending work that
    /// has accumulated while the app was suspended. The completion handler
    /// must be invoked by the caller after this returns.
    func runBackgroundTick() {
        ingestor.fetchOnDemand()
    }

    /// Stop ingestion. Used on permission denial or explicit user disable.
    func stop() {
        ingestor.stop()
        updateStatus(.idle)
    }

    // MARK: - Internals

    private func handleNewRRBatch(_ rawBatch: [RRSample]) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let filtered = RRQualityFilter.filter(rawBatch)
            guard !filtered.isEmpty else { return }
            let windows = self.assembler.ingest(filtered)
            self.store.saveAssembler(self.assembler)
            for window in windows {
                self.scoreWindow(window)
            }
        }
    }

    private func scoreWindow(_ window: WindowAssembler.EmittedWindow) {
        let probability: Float
        do {
            probability = try classifier.predict(scaledWindow: window.scaled)
        } catch {
            NSLog("AFClassifier prediction failed: \(error.localizedDescription)")
            return
        }
        let record = InferenceRecord(
            id: UUID(),
            timestamp: Date(),
            probability: probability,
            isPositive: probability >= AFConstants.afProbabilityThreshold,
            validSampleCount: window.validSampleCount
        )
        store.appendInference(record)
        let transition = stateMachine.observe(record)
        store.saveStateMachine(stateMachine)
        store.saveMonitoringStatus(stateMachine.status)

        if transition == .raisedWarning {
            let alert = AFAlert(id: UUID(),
                                timestamp: record.timestamp,
                                triggeringProbability: record.probability)
            store.appendAlert(alert)
            notifier.notifyAFDetected(probability: record.probability)
        }

        let snapshotStatus = stateMachine.status
        let latestAlert = store.loadRecentAlerts().last
        let recent = store.loadRecentInferences()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastInference = record
            self.recentInferences = recent
            self.status = snapshotStatus
        }
        WatchSessionManager.shared.sendSnapshot(
            status: snapshotStatus,
            lastInference: record,
            latestAlert: latestAlert
        )
    }

    private func updateStatus(_ newStatus: MonitoringStatus) {
        stateMachine.setStatus(newStatus)
        store.saveStateMachine(stateMachine)
        store.saveMonitoringStatus(newStatus)
        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
        }
        WatchSessionManager.shared.sendSnapshot(
            status: newStatus,
            lastInference: lastInference,
            latestAlert: store.loadRecentAlerts().last
        )
    }
}
