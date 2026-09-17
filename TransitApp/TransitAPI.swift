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

protocol TransitProvider: Sendable {
    var providerID: String { get }
    var endpoints: [TransitEndpoint] { get }
    func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot
}

struct TransitHTTPClient: Sendable {
    var session: URLSession = .shared

    func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TransitError.invalidResponse(url)
        }
        do {
            return try JSONDecoder.transit.decode(type, from: data)
        } catch {
            throw TransitError.decoding(provider: url.host ?? "Transit", underlying: error.localizedDescription)
        }
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
        struct Response: Decodable { let data: [Stop] }
        let response = try await client.get(Response.self, from: endpoints[0].url)
        return TransitSnapshot(stops: response.data.map {
            TransitStop(id: $0.stop, name: $0.nameEn, coordinate: .init(latitude: $0.lat, longitude: $0.long), provider: providerID)
        })
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
        guard let latitude = Double(response.data.lat), let longitude = Double(response.data.long) else {
            throw TransitError.decoding(provider: providerID, underlying: "Invalid coordinates")
        }
        return TransitSnapshot(stops: [
            TransitStop(id: response.data.stop, name: response.data.nameEn, coordinate: .init(latitude: latitude, longitude: longitude), provider: providerID)
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
            guard let latitude = Double(stop.latitude), let longitude = Double(stop.longitude) else { return nil }
            return TransitStop(id: stop.stopId, name: stop.name, coordinate: .init(latitude: latitude, longitude: longitude), provider: providerID)
        }
        return TransitSnapshot(stops: stops)
    }
}

struct TransitProviderRegistry: Sendable {
    let providers: [any TransitProvider]

    init() {
        providers = [KMBProvider(), CitybusProvider(), NLBProvider(), MTRProvider()]
    }

    func fetchAll(using client: TransitHTTPClient) async -> (TransitSnapshot, [FeedStatus]) {
        let results = await withTaskGroup(of: (TransitSnapshot, FeedStatus).self, returning: [(TransitSnapshot, FeedStatus)].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let snapshot = try await provider.fetchSnapshot(using: client)
                        return (snapshot, FeedStatus(id: provider.providerID, name: provider.providerID, mode: provider.endpoints.first?.mode ?? .unknown, sourceURL: provider.endpoints.first?.url ?? URL(string: "https://data.gov.hk")!, lastUpdated: .now, isAvailable: true, message: nil))
                    } catch {
                        return (TransitSnapshot(), FeedStatus(id: provider.providerID, name: provider.providerID, mode: provider.endpoints.first?.mode ?? .unknown, sourceURL: provider.endpoints.first?.url ?? URL(string: "https://data.gov.hk")!, lastUpdated: nil, isAvailable: false, message: error.localizedDescription))
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
        TransitSnapshot(
            stops: Array(Set(stops + other.stops)),
            routes: Array(Set(routes + other.routes)),
            arrivals: Array(Set(arrivals + other.arrivals)),
            alerts: Array(Set(alerts + other.alerts)),
            fetchedAt: max(fetchedAt, other.fetchedAt)
        )
    }
}
