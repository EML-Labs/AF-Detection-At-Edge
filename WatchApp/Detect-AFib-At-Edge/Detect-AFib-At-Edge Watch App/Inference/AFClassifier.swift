import Foundation
import CoreML

/// On-device wrapper around the AF Core ML classifier.
///
/// The model from Part 1 is expected to:
///   - take an input named `rr_intervals_scaled` of shape `[1, 200]` (Float32)
///   - return a single AF probability output named `probability` (Float32 in [0, 1])
///
/// Drop the exported `AFClassifier.mlpackage` (or `AFClassifier.mlmodel`) into
/// the watch app's synchronized folder and Xcode will compile it into the
/// bundle as `AFClassifier.mlmodelc` automatically.
///
/// Until that ships, this wrapper falls back to a deterministic mock
/// probability derived from RR irregularity so the rest of the pipeline,
/// state machine and UI can be exercised end-to-end.
final class AFClassifier {
    enum AFClassifierError: Error {
        case predictionFailed(String)
        case malformedOutput
    }

    private let model: MLModel?
    private let probabilityFeatureName: String
    private let inputFeatureName: String

    init() {
        let candidateNames = ["AFClassifier", "AFibClassifier", "model"]
        var loadedModel: MLModel?
        for name in candidateNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                loadedModel = try? MLModel(contentsOf: url)
                if loadedModel != nil { break }
            }
        }
        self.model = loadedModel
        self.inputFeatureName = "rr_intervals_scaled"
        if let description = loadedModel?.modelDescription {
            let preferred = ["probability", "Identity", "output", "logit", "logits"]
            let firstMatch = preferred.first { description.outputDescriptionsByName[$0] != nil }
            self.probabilityFeatureName = firstMatch
                ?? description.outputDescriptionsByName.keys.first
                ?? "probability"
        } else {
            self.probabilityFeatureName = "probability"
        }
    }

    /// True when a real Core ML model is bundled and loaded.
    var isUsingBundledModel: Bool { model != nil }

    /// Run one inference for a window of scaled RR intervals.
    ///
    /// - Parameter scaledWindow: array of length `AFConstants.windowSize` of
    ///   Float32 values produced by `RobustScaler.scale(_:)`.
    /// - Returns: AF probability in [0, 1].
    func predict(scaledWindow: [Float]) throws -> Float {
        precondition(scaledWindow.count == AFConstants.windowSize,
                     "AFClassifier requires exactly \(AFConstants.windowSize) values per window.")
        if let model = model {
            return try predictWithCoreML(model: model, scaledWindow: scaledWindow)
        }
        return mockProbability(for: scaledWindow)
    }

    private func predictWithCoreML(model: MLModel, scaledWindow: [Float]) throws -> Float {
        let shape: [NSNumber] = [1, NSNumber(value: scaledWindow.count)]
        let array: MLMultiArray
        do {
            array = try MLMultiArray(shape: shape, dataType: .float32)
        } catch {
            throw AFClassifierError.predictionFailed("Failed to allocate input MLMultiArray: \(error)")
        }
        scaledWindow.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                array.dataPointer
                    .bindMemory(to: Float32.self, capacity: scaledWindow.count)
                    .update(from: base, count: scaledWindow.count)
            }
        }

        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [inputFeatureName: array])
        } catch {
            throw AFClassifierError.predictionFailed("Failed to build input provider: \(error)")
        }

        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            throw AFClassifierError.predictionFailed("Core ML prediction failed: \(error)")
        }

        guard let value = prediction.featureValue(for: probabilityFeatureName) else {
            throw AFClassifierError.malformedOutput
        }

        if value.type == .double {
            return Float(value.doubleValue).clampedTo01
        }
        if let multi = value.multiArrayValue, multi.count >= 1 {
            let raw = multi[0].floatValue
            return raw.clampedTo01
        }
        if let dict = value.dictionaryValue as? [Int: Double], let positive = dict[1] {
            return Float(positive).clampedTo01
        }
        if let dict = value.dictionaryValue as? [String: Double] {
            for key in ["1", "AF", "afib", "positive"] {
                if let positive = dict[key] {
                    return Float(positive).clampedTo01
                }
            }
        }
        throw AFClassifierError.malformedOutput
    }

    /// Deterministic placeholder for development without the production model.
    /// Maps RR irregularity (mean absolute successive difference of the scaled
    /// window) to a probability in [0, 1].
    private func mockProbability(for scaledWindow: [Float]) -> Float {
        guard scaledWindow.count > 1 else { return 0 }
        var sumAbsDiff: Float = 0
        for i in 1..<scaledWindow.count {
            sumAbsDiff += abs(scaledWindow[i] - scaledWindow[i - 1])
        }
        let masd = sumAbsDiff / Float(scaledWindow.count - 1)
        let probability = 1 / (1 + expf(-(masd - 0.6) * 4))
        return probability.clampedTo01
    }
}

private extension Float {
    var clampedTo01: Float { Swift.max(0, Swift.min(1, self)) }
}
