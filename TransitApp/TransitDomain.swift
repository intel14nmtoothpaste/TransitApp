import CoreLocation
import Foundation

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

struct TransitStop: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate
    let provider: String

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

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

    var minutesAway: Int? {
        guard let expectedAt else { return nil }
        return max(0, Int(ceil(expectedAt.timeIntervalSinceNow / 60)))
    }
}

struct ServiceAlert: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let message: String
    let provider: String
    let publishedAt: Date
    let severity: Severity

    enum Severity: String, Codable, Sendable {
        case info
        case warning
        case critical
    }
}

struct TransitSnapshot: Codable, Sendable {
    var stops: [TransitStop] = []
    var routes: [TransitRoute] = []
    var arrivals: [Arrival] = []
    var alerts: [ServiceAlert] = []
    var fetchedAt: Date = .now
}

struct FeedStatus: Identifiable, Sendable {
    let id: String
    let name: String
    let mode: TransitMode
    let sourceURL: URL
    let lastUpdated: Date?
    let isAvailable: Bool
    let message: String?
}

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
