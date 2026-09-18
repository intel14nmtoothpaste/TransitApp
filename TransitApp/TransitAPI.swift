import Foundation

struct TransitEndpoint: Identifiable, Sendable {
    let id: String
    let provider: String
    let mode: TransitMode
    let purpose: String
    let url: URL
    let refreshInterval: TimeInterval
}

enum HongKongTransitCatalog {
    static let endpoints: [TransitEndpoint] = [
        .init(id: "kmb-stops", provider: "KMB", mode: .bus, purpose: "All KMB stops", url: URL(string: "https://data.etabus.gov.hk/v1/transport/kmb/stop")!, refreshInterval: 86_400),
        .init(id: "kmb-routes", provider: "KMB", mode: .bus, purpose: "KMB route list", url: URL(string: "https://data.etabus.gov.hk/v1/transport/kmb/route")!, refreshInterval: 86_400),
        .init(id: "citybus-stops", provider: "Citybus", mode: .bus, purpose: "Citybus stop and route feeds", url: URL(string: "https://rt.data.gov.hk/v2/transport/citybus/stop/001007")!, refreshInterval: 86_400),
        .init(id: "nlb-stops", provider: "NLB", mode: .bus, purpose: "NLB stop list", url: URL(string: "https://rt.data.gov.hk/v2/transport/nlb/stop.php?action=list&routeId=1A")!, refreshInterval: 86_400),
        .init(id: "mtr-schedule", provider: "MTR", mode: .rail, purpose: "MTR real-time train schedule", url: URL(string: "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=TCL&sta=HOK")!, refreshInterval: 30),
        .init(id: "light-rail-schedule", provider: "MTR", mode: .lightRail, purpose: "Light Rail platform schedule", url: URL(string: "https://rt.data.gov.hk/v1/transport/mtr/lrt/getSchedule?station_id=001")!, refreshInterval: 30),
        .init(id: "geodata-search", provider: "Hong Kong Geodata", mode: .unknown, purpose: "Place and stop search", url: URL(string: "https://geodata.gov.hk/gs/api/v1.0.0/locationSearch?q=Central")!, refreshInterval: 3_600),
        .init(id: "route-fares", provider: "Open Hong Kong Transit", mode: .bus, purpose: "Cross-operator route and fare metadata", url: URL(string: "https://data.hkbus.app/routeFareList.min.json")!, refreshInterval: 86_400)
    ]
}

protocol TransitProviderAdapter: Sendable {
    var providerID: String { get }
    var endpoints: [TransitEndpoint] { get }
    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot
    func normalize(_ snapshot: TransitSnapshot) -> TransitSnapshot
}

/// Provider implementations decode their payloads and return the app's stable model.
protocol TransitProvider: TransitProviderAdapter {}

extension TransitProviderAdapter {
    func normalize(_ snapshot: TransitSnapshot) -> TransitSnapshot {
        TransitNormalizer().normalize(snapshot)
    }
}

struct TransitHTTPClient: Sendable {
    var session: URLSession = .shared
    var maxAttempts: Int = 3
    var baseRetryDelay: TimeInterval = 0.5

    func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var attempt = 0
        while true {
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TransitError.invalidResponse(url)
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw TransitError.invalidResponse(url)
                }
                do {
                    return try JSONDecoder.transit.decode(type, from: data)
                } catch {
                    throw TransitError.decoding(provider: url.host ?? "Transit", underlying: error.localizedDescription)
                }
            } catch {
                attempt += 1
                guard attempt < max(1, maxAttempts), Self.isRetryable(error) else { throw error }
                let delay = baseRetryDelay * pow(2, Double(attempt - 1))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code)
        }
        if case TransitError.invalidResponse = error { return true }
        return false
    }
}

extension JSONDecoder {
    static var transit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct KMBProvider: TransitProvider {
    let providerID = "KMB"
    let endpoints = HongKongTransitCatalog.endpoints.filter { $0.provider == "KMB" }

    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot {
        struct Stop: Decodable {
            let stop: String
            let nameEn: String
            let lat: Double
            let long: Double
            enum CodingKeys: String, CodingKey { case stop, nameEn = "name_en", lat, long }
        }
        struct Route: Decodable {
            let route: String
            let bound: String?
            let origin: String
            let destination: String
            enum CodingKeys: String, CodingKey { case route, bound, origin, destination }
        }
        struct StopResponse: Decodable { let data: [Stop] }
        struct RouteResponse: Decodable { let data: [Route] }
        let response = try await client.get(StopResponse.self, from: endpoints[0].url)
        var snapshot = TransitSnapshot(stops: response.data.map {
            TransitStop(id: $0.stop, name: $0.nameEn, coordinate: .init(latitude: $0.lat, longitude: $0.long), provider: providerID)
        })
        if let routeEndpoint = endpoints.first(where: { $0.id == "kmb-routes" }) {
            let routes = try await client.get(RouteResponse.self, from: routeEndpoint.url).data
            snapshot.routes = routes.map {
                TransitRoute(id: "\($0.route)-\($0.bound ?? "")", operatorName: providerID, number: $0.route,
                             origin: $0.origin, destination: $0.destination, mode: .bus, accessible: false, stopIDs: [])
            }
        }
        return snapshot
    }
}

struct MTRProvider: TransitProvider {
    let providerID = "MTR"
    let endpoints = HongKongTransitCatalog.endpoints.filter { $0.provider == "MTR" || $0.provider == "Hong Kong Geodata" }

    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot {
        struct Schedule: Decodable { let time: String; let dest: String }
        struct Line: Decodable { let up: [Schedule]?; let down: [Schedule]?; enum CodingKeys: String, CodingKey { case up = "UP"; case down = "DOWN" } }
        struct Response: Decodable { let data: [String: Line] }
        let response = try await client.get(Response.self, from: endpoints[0].url)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let arrivals = response.data.values.flatMap { ($0.up ?? []) + ($0.down ?? []) }.compactMap { schedule -> Arrival? in
            guard let time = formatter.date(from: schedule.time) else { return nil }
            return Arrival(id: "MTR-\(schedule.time)-\(schedule.dest)", routeID: "MTR", routeNumber: "MTR", destination: schedule.dest, mode: .rail, expectedAt: time, status: nil, provider: providerID, observedAt: .now)
        }
        return TransitSnapshot(arrivals: arrivals)
    }
}

struct CitybusProvider: TransitProvider {
    let providerID = "Citybus"
    let endpoints = HongKongTransitCatalog.endpoints.filter { $0.provider == "Citybus" }

    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot {
        struct Stop: Decodable {
            let stop: String
            let nameEn: String
            let lat: String
            let long: String
            enum CodingKeys: String, CodingKey { case stop, nameEn = "name_en", lat, long }
        }
        struct Response: Decodable { let data: Stop }
        let response = try await client.get(Response.self, from: endpoints[0].url)
        let coordinate = try TransitCoordinateParser.coordinate(latitude: response.data.lat, longitude: response.data.long, provider: providerID)
        return TransitSnapshot(stops: [
            TransitStop(id: response.data.stop, name: response.data.nameEn, coordinate: coordinate, provider: providerID)
        ])
    }
}

struct NLBProvider: TransitProvider {
    let providerID = "NLB"
    let endpoints = HongKongTransitCatalog.endpoints.filter { $0.provider == "NLB" }

    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot {
        struct Stop: Decodable {
            let stopId: String
            let name: String
            let latitude: String
            let longitude: String
            enum CodingKeys: String, CodingKey {
                case stopId
                case name = "stopName_e"
                case latitude
                case longitude
            }
        }
        struct Response: Decodable { let stops: [Stop]?; let data: [Stop]? }
        let response = try await client.get(Response.self, from: endpoints[0].url)
        let stops = (response.stops ?? response.data ?? []).compactMap { stop -> TransitStop? in
            guard let coordinate = try? TransitCoordinateParser.coordinate(latitude: stop.latitude, longitude: stop.longitude, provider: providerID) else { return nil }
            return TransitStop(id: stop.stopId, name: stop.name, coordinate: coordinate, provider: providerID)
        }
        return TransitSnapshot(stops: stops)
    }
}

enum TransitCoordinateParser {
    static func coordinate(latitude: String, longitude: String, provider: String) throws -> Coordinate {
        guard let latitudeValue = Double(latitude), let longitudeValue = Double(longitude) else {
            throw TransitError.decoding(provider: provider, underlying: "Invalid coordinates")
        }
        return Coordinate(latitude: latitudeValue, longitude: longitudeValue)
    }
}

extension TransitProvider {
    var fallbackEndpoint: TransitEndpoint {
        endpoints.first ?? TransitEndpoint(
            id: providerID,
            provider: providerID,
            mode: .unknown,
            purpose: "Fallback endpoint",
            url: URL(string: "https://data.gov.hk")!,
            refreshInterval: 0
        )
    }

    func makeFeedStatus(isAvailable: Bool, lastUpdated: Date? = nil, message: String? = nil, consecutiveFailures: Int = 0) -> FeedStatus {
        let stale = lastUpdated.map { Date().timeIntervalSince($0) > fallbackEndpoint.refreshInterval } ?? true
        return FeedStatus(
            id: providerID,
            name: providerID,
            mode: fallbackEndpoint.mode,
            sourceURL: fallbackEndpoint.url,
            lastUpdated: lastUpdated,
            isAvailable: isAvailable,
            message: message,
            health: isAvailable ? (stale ? .stale : .healthy) : .unavailable,
            consecutiveFailures: consecutiveFailures
        )
    }
}

struct TransitProviderRegistry: Sendable {
    let providers: [any TransitProvider]

    init(providers: [any TransitProvider] = [KMBProvider(), CitybusProvider(), NLBProvider(), MTRProvider()]) {
        self.providers = providers
    }

    func fetchAll(using client: TransitHTTPClient) async -> (TransitSnapshot, [FeedStatus]) {
        let results = await withTaskGroup(of: (TransitSnapshot, FeedStatus).self, returning: [(TransitSnapshot, FeedStatus)].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let snapshot = provider.normalize(try await provider.fetchSnapshot(using: client))
                        return (snapshot, provider.makeFeedStatus(isAvailable: true, lastUpdated: .now))
                    } catch {
                        return (TransitSnapshot(), provider.makeFeedStatus(isAvailable: false, message: error.localizedDescription, consecutiveFailures: client.maxAttempts))
                    }
                }
            }
            var results: [(TransitSnapshot, FeedStatus)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        var snapshot = TransitSnapshot()
        var statuses: [FeedStatus] = []
        for result in results {
            snapshot = snapshot.merged(with: result.0)
            statuses.append(result.1)
        }
        return (snapshot, statuses)
    }
}

extension TransitSnapshot {
    func merged(with other: TransitSnapshot) -> TransitSnapshot {
        var mergedStops: [String: TransitStop] = [:]
        var mergedRoutes: [String: TransitRoute] = [:]
        var mergedArrivals: [String: Arrival] = [:]
        var mergedAlerts: [String: ServiceAlert] = [:]

        for item in stops { mergedStops[item.id] = item }
        for item in other.stops { mergedStops[item.id] = item }
        for item in routes { mergedRoutes[item.id] = item }
        for item in other.routes { mergedRoutes[item.id] = item }
        for item in arrivals { mergedArrivals[item.id] = item }
        for item in other.arrivals { mergedArrivals[item.id] = item }
        for item in alerts { mergedAlerts[item.id] = item }
        for item in other.alerts { mergedAlerts[item.id] = item }

        return TransitSnapshot(
            stops: Array(mergedStops.values),
            routes: Array(mergedRoutes.values),
            arrivals: Array(mergedArrivals.values),
            alerts: Array(mergedAlerts.values),
            fetchedAt: max(fetchedAt, other.fetchedAt)
        )
    }
}
