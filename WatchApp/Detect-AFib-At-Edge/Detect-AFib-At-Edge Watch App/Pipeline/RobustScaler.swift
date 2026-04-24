import Foundation

/// Mirror of sklearn's `RobustScaler` for the patient-specific RR scaling
/// applied during training. Defined as a pure function so it can be
/// unit-tested for parity against the Python reference.
///
/// Scaling: `scaled = (rr - median) / scale`
enum RobustScaler {
    /// Scale a window of RR intervals (milliseconds) to model input space.
    static func scale(_ rrIntervalsMs: [Double],
                      median: Float = AFConstants.RobustScalerParams.median,
                      scale: Float = AFConstants.RobustScalerParams.scale) -> [Float] {
        precondition(scale != 0, "RobustScaler scale must be non-zero")
        let invScale = 1 / scale
        var output = [Float](repeating: 0, count: rrIntervalsMs.count)
        for (i, value) in rrIntervalsMs.enumerated() {
            output[i] = (Float(value) - median) * invScale
        }
        return output
    }
}
