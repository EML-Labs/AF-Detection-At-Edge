import Foundation

struct AFAlert: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let triggeringProbability: Float
}
