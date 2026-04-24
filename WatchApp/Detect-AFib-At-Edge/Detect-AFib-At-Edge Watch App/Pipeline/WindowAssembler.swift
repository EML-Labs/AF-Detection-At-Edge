import Foundation

/// Combines the rolling buffer + scaler to produce model-ready scaled windows.
///
/// Designed as a value-type owner of the buffer so the inference coordinator
/// can persist its state in shared storage between background wakes.
struct WindowAssembler: Codable {
    private(set) var buffer: RollingRRBuffer
    private(set) var firstEmissionDone: Bool

    init(buffer: RollingRRBuffer = RollingRRBuffer(),
         firstEmissionDone: Bool = false) {
        self.buffer = buffer
        self.firstEmissionDone = firstEmissionDone
    }

    /// One model-ready window plus the count of valid RR samples it contained
    /// (which equals `windowSize` here because the buffer only holds
    /// quality-filtered samples, but is exposed for symmetry and for future
    /// QC-aware variants).
    struct EmittedWindow {
        let scaled: [Float]
        let validSampleCount: Int
        /// Timestamp of the most recent RR sample in the window.
        let endTimestamp: Date
    }

    /// Append filtered RR samples and return as many new windows as can be
    /// produced (bounded by `maxToEmit`).
    mutating func ingest(_ filtered: [RRSample], maxToEmit: Int = AFConstants.maxWindowsPerWake) -> [EmittedWindow] {
        buffer.append(filtered)
        var windows: [EmittedWindow] = []
        while windows.count < maxToEmit && buffer.canEmitWindow(firstEmissionDone: firstEmissionDone) {
            let windowSamples = buffer.mostRecentWindow()
            let raw = windowSamples.map(\.intervalMs)
            let scaled = RobustScaler.scale(raw)
            let endTimestamp = windowSamples.last?.timestamp ?? Date()
            windows.append(EmittedWindow(scaled: scaled,
                                         validSampleCount: windowSamples.count,
                                         endTimestamp: endTimestamp))
            buffer.recordEmission()
            firstEmissionDone = true
            if !buffer.canEmitWindow(firstEmissionDone: firstEmissionDone) { break }
        }
        return windows
    }
}
