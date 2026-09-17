import Foundation

/// Contract for an optional server-side normalizer. The app can use direct open
/// feeds by default and inject an implementation for high-frequency ETA polling.
protocol TransitAggregationClient: Sendable {
    func snapshot(for coordinate: Coordinate?, providers: [String]) async throws -> TransitSnapshot
}

struct AggregationConfiguration: Codable, Sendable {
    var baseURL: URL?
    var apiVersion = "v1"
    var requiresAuthentication = false
    var supportedProviders: [String] = []
}
