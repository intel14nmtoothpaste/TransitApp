import CoreLocation
import Foundation

/// Identifies the transport class used when rendering icons, labels, and route filtering.
enum TransitMode: String, Codable, CaseIterable, Identifiable {
    case bus
    case minibus
    case rail
    case lightRail
    case ferry
    case tram
    case unknown

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bus, .minibus: return "bus"
        case .rail, .lightRail: return "train.side.front.car"
        case .ferry: return "ferry"
        case .tram: return "tram"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// A station or platform returned from a provider feed.
struct TransitStop: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate
    let provider: String

    /// Converts the custom coordinate representation into the Core Location type used by the map view.
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// Basic geospatial coordinate used throughout the app's transport model.
struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A service route as published by a transit provider.
struct TransitRoute: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let operatorName: String
    let number: String
    let origin: String
    let destination: String
    let mode: TransitMode
    let accessible: Bool
    let stopIDs: [String]
}

/// A single next-arrival estimate for a stop, route, or line.
struct Arrival: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let routeID: String
    let routeNumber: String
    let destination: String
    let mode: TransitMode
    let expectedAt: Date?
    let status: String?
    let provider: String
    let observedAt: Date

    /// Returns the arrival time in whole minutes, clamped to zero when the feed is already due.
    var minutesAway: Int? {
        guard let expectedAt else { return nil }
        return max(0, Int(ceil(expectedAt.timeIntervalSinceNow / 60)))
    }
}

/// A user-facing service message for a provider or route area.
struct ServiceAlert: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let message: String
    let provider: String
    let publishedAt: Date
    let severity: Severity

    /// Severity level from informational updates to active incidents.
    enum Severity: String, Codable, Sendable {
        case info
        case warning
        case critical
    }
}

/// The complete payload returned by a refresh cycle, including cached provider data.
struct TransitSnapshot: Codable, Sendable {
    var stops: [TransitStop] = []
    var routes: [TransitRoute] = []
    var arrivals: [Arrival] = []
    var alerts: [ServiceAlert] = []
    var fetchedAt: Date = .now
}

/// Operational readiness for an upstream transit feed.
struct FeedStatus: Identifiable, Sendable {
    let id: String
    let name: String
    let mode: TransitMode
    let sourceURL: URL
    let lastUpdated: Date?
    let isAvailable: Bool
    let message: String?
    let health: FeedHealth
    let consecutiveFailures: Int

    init(id: String, name: String, mode: TransitMode, sourceURL: URL, lastUpdated: Date?, isAvailable: Bool, message: String?, health: FeedHealth = .unknown, consecutiveFailures: Int = 0) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sourceURL = sourceURL
        self.lastUpdated = lastUpdated
        self.isAvailable = isAvailable
        self.message = message
        self.health = health
        self.consecutiveFailures = consecutiveFailures
    }
}

/// Resulting health of a provider feed after a network or parsing attempt.
enum FeedHealth: String, Codable, Sendable {
    case healthy
    case stale
    case unavailable
    case unknown
}

/// Standardized error surfaced by the transit data layer.
enum TransitError: LocalizedError, Sendable {
    case invalidResponse(URL)
    case unavailable(provider: String, underlying: String)
    case decoding(provider: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let url): return "The transit feed returned an invalid response: \(url.host ?? url.absoluteString)."
        case .unavailable(let provider, let underlying): return "\(provider) is currently unavailable. \(underlying)"
        case .decoding(let provider, let underlying): return "\(provider) returned data in an unexpected format. \(underlying)"
        }
    }
}
