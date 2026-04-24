import Foundation

struct InferenceRecord: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let probability: Float
    let isPositive: Bool
    let validSampleCount: Int
}
