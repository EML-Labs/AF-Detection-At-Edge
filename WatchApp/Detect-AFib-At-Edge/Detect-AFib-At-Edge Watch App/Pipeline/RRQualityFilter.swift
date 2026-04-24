import Foundation

/// Pure function that drops RR samples that are physiologically implausible
/// or that HealthKit flagged as following a gap (missed beat / detector
/// dropout). Mirrors the cleaning step used during training preprocessing.
enum RRQualityFilter {
    static func filter(_ samples: [RRSample]) -> [RRSample] {
        samples.filter { sample in
            guard !sample.precededByGap else { return false }
            return sample.intervalMs >= AFConstants.minValidRRMs
                && sample.intervalMs <= AFConstants.maxValidRRMs
        }
    }
}
