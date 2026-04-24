import Foundation

enum MonitoringStatus: String, Codable, Hashable {
    case idle
    case collecting
    case monitoring
    case lowQuality
    case warning
}
