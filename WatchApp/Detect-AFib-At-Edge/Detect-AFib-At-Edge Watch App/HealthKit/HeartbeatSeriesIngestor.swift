import Foundation
import HealthKit

/// Continuously delivers RR intervals derived from `HKHeartbeatSeriesSample`
/// records produced by Apple's PPG pipeline (typically during workouts and
/// background heart studies). The watch app does not generate these series
/// itself; we observe new ones, enumerate their inter-beat intervals, and
/// hand them off to the inference pipeline.
///
/// The ingestor relies on:
///   - `HKObserverQuery` with background delivery to be woken when new
///     series are written.
///   - `HKAnchoredObjectQuery` to fetch only the new series since the last
///     wake. The anchor is persisted in the shared App Group store so it
///     survives app termination and background refresh cycles.
///   - `HKHeartbeatSeriesQuery` to enumerate the inter-beat intervals
///     within each series (with their `precededByGap` flag).
final class HeartbeatSeriesIngestor {
    typealias RRBatchHandler = ([RRSample]) -> Void

    private let healthStore: HKHealthStore
    private let sampleType: HKSeriesType
    private let store: SharedStore

    private var observerQuery: HKObserverQuery?
    private var rrBatchHandler: RRBatchHandler?

    init(healthStore: HKHealthStore = HealthKitManager.shared.healthStore,
         sampleType: HKSeriesType = HealthKitManager.shared.heartbeatSeriesType,
         store: SharedStore = .shared) {
        self.healthStore = healthStore
        self.sampleType = sampleType
        self.store = store
    }

    /// Start observing new heart-beat series. The handler is invoked off the
    /// main thread for each batch of newly-extracted RR intervals.
    func start(onNewRRBatch handler: @escaping RRBatchHandler) {
        rrBatchHandler = handler

        let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
            defer { completion() }
            if let error = error {
                NSLog("HeartbeatSeriesIngestor observer error: \(error.localizedDescription)")
                return
            }
            self?.fetchNewSeries()
        }
        observerQuery = observer
        healthStore.execute(observer)

        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
            if let error = error {
                NSLog("HeartbeatSeriesIngestor enableBackgroundDelivery error: \(error.localizedDescription)")
            } else if !success {
                NSLog("HeartbeatSeriesIngestor enableBackgroundDelivery returned false")
            }
        }
    }

    /// Stop observing. Used when permission is revoked or the user disables
    /// monitoring from the UI.
    func stop() {
        if let observer = observerQuery {
            healthStore.stop(observer)
            observerQuery = nil
        }
        healthStore.disableBackgroundDelivery(for: sampleType) { _, _ in }
    }

    /// Manually trigger a fetch (e.g. on app launch or background refresh)
    /// independent of an observer callback.
    func fetchOnDemand() {
        fetchNewSeries()
    }

    private func fetchNewSeries() {
        let anchor = store.loadAnchor()
        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            guard let self = self else { return }
            if let error = error {
                NSLog("HeartbeatSeriesIngestor anchored query error: \(error.localizedDescription)")
                return
            }
            if let newAnchor = newAnchor {
                self.store.saveAnchor(newAnchor)
            }
            guard let series = samples as? [HKHeartbeatSeriesSample], !series.isEmpty else { return }
            self.enumerateIntervals(for: series)
        }
        healthStore.execute(query)
    }

    private func enumerateIntervals(for samples: [HKHeartbeatSeriesSample]) {
        let group = DispatchGroup()
        var collected: [RRSample] = []
        let collector = DispatchQueue(label: "afib.ingestor.collector")

        for sample in samples {
            group.enter()
            var intervals: [RRSample] = []
            let baseTime = sample.startDate
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceStart, precededByGap, done, error in
                if let error = error {
                    NSLog("HeartbeatSeriesQuery enumeration error: \(error.localizedDescription)")
                }
                if !done && error == nil {
                    let beatTime = baseTime.addingTimeInterval(timeSinceStart)
                    intervals.append(RRSample(
                        intervalMs: 0,
                        timestamp: beatTime,
                        precededByGap: precededByGap
                    ))
                }
                if done {
                    let withDeltas = Self.computeRRIntervals(beats: intervals)
                    collector.sync { collected.append(contentsOf: withDeltas) }
                    group.leave()
                }
            }
            healthStore.execute(query)
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            collected.sort { $0.timestamp < $1.timestamp }
            if !collected.isEmpty {
                self?.rrBatchHandler?(collected)
            }
        }
    }

    /// Convert a list of beat events (with gap flags) into RR intervals.
    /// The first beat in each series has no preceding interval and is dropped;
    /// each subsequent interval inherits the `precededByGap` flag of its
    /// closing beat so the quality filter can drop tainted intervals.
    static func computeRRIntervals(beats: [RRSample]) -> [RRSample] {
        guard beats.count >= 2 else { return [] }
        var result: [RRSample] = []
        result.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count {
            let delta = beats[i].timestamp.timeIntervalSince(beats[i - 1].timestamp) * 1000
            result.append(RRSample(
                intervalMs: delta,
                timestamp: beats[i].timestamp,
                precededByGap: beats[i].precededByGap
            ))
        }
        return result
    }
}
