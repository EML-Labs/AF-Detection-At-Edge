import Foundation

/// Persistent rolling buffer of validated RR intervals.
///
/// Holds at most `AFConstants.bufferCapacity` samples and tracks how many of
/// them have already been consumed by a window emission, so the assembler
/// can advance by exactly `AFConstants.stride` after every emit.
///
/// Thread-safety: external callers must serialize access. The
/// `InferenceCoordinator` owns and serializes all access via its own
/// dispatch queue.
struct RollingRRBuffer: Codable {
    private(set) var samples: [RRSample]
    /// Number of samples consumed since the last buffer reset.
    /// Used together with `samples.count` to determine when a new window can
    /// be emitted: a window is ready when there are at least `windowSize`
    /// samples since the last emission.
    private(set) var samplesSinceLastEmission: Int

    init(samples: [RRSample] = [], samplesSinceLastEmission: Int = 0) {
        self.samples = samples
        self.samplesSinceLastEmission = samplesSinceLastEmission
    }

    /// Append validated RR intervals to the buffer, trimming oldest entries
    /// when the capacity is exceeded.
    mutating func append(_ newSamples: [RRSample]) {
        guard !newSamples.isEmpty else { return }
        samples.append(contentsOf: newSamples)
        samplesSinceLastEmission += newSamples.count
        if samples.count > AFConstants.bufferCapacity {
            let overflow = samples.count - AFConstants.bufferCapacity
            samples.removeFirst(overflow)
        }
    }

    /// True when enough fresh samples have arrived to emit a new window.
    /// Returns false until the very first window (which requires `windowSize`
    /// samples), and after that requires `stride` fresh samples per emission.
    func canEmitWindow(firstEmissionDone: Bool) -> Bool {
        guard samples.count >= AFConstants.windowSize else { return false }
        if !firstEmissionDone { return true }
        return samplesSinceLastEmission >= AFConstants.stride
    }

    /// Mark a window emission. After an emission the stride accumulator is
    /// reset to zero, so the next emission requires exactly `stride` fresh
    /// samples regardless of how much "credit" was carried over from the
    /// previous append.
    mutating func recordEmission() {
        samplesSinceLastEmission = 0
    }

    /// The most recent `windowSize` samples (the window assembler reads from
    /// the tail of the buffer).
    func mostRecentWindow() -> [RRSample] {
        guard samples.count >= AFConstants.windowSize else { return [] }
        return Array(samples.suffix(AFConstants.windowSize))
    }
}
