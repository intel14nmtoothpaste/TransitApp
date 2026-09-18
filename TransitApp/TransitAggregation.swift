import Foundation

/// Contract for an optional server-side normalizer. The app can use direct open
/// feeds by default and inject an implementation for high-frequency ETA polling.
/// Optional abstraction for a server-side ETA normalizer or aggregation service.
protocol TransitAggregationClient: Sendable {
    func snapshot(for coordinate: Coordinate?, providers: [String]) async throws -> TransitSnapshot
}

/// Normalizes provider payloads before they are merged into the app's main store.
struct TransitNormalizer: Sendable {
    /// Applies provider-independent rules once, after every adapter has decoded its payload.
    ///
    /// This currently removes duplicate IDs and invalid coordinates so the UI never renders
    /// impossible stop locations or duplicate entries from partial provider updates.
    func normalize(_ snapshot: TransitSnapshot) -> TransitSnapshot {
        var normalized = snapshot
        normalized.stops = unique(normalized.stops).filter {
            (-90...90).contains($0.coordinate.latitude) && (-180...180).contains($0.coordinate.longitude)
        }
        normalized.routes = unique(normalized.routes)
        normalized.arrivals = unique(normalized.arrivals)
        normalized.alerts = unique(normalized.alerts)
        return normalized
    }

    private func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }
}

struct AggregationConfiguration: Codable, Sendable {
    var baseURL: URL?
    var apiVersion = "v1"
    var requiresAuthentication = false
    var supportedProviders: [String] = []
}
