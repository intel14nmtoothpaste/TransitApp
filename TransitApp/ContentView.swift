import SwiftUI
import MapKit
import CoreData
import Combine
import UserNotifications
import AVFoundation
import CoreLocation
import Foundation
import CryptoKit

    // MARK: - API Client Protocol
protocol APIClient {
    func fetch<T: Codable>(_ url: URL) async throws -> T
}

    // MARK: - SearchField Enum
enum SearchField: Hashable {
    case origin
    case destination
}

    // MARK: - Equatable Conformance for CLLocationCoordinate2D
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        let tolerance = 0.0001
        return abs(lhs.latitude - rhs.latitude) < tolerance &&
        abs(lhs.longitude - rhs.longitude) < tolerance
    }
}

    // MARK: - UserDefaults Extension
extension UserDefaults {
    func saveRecentSearches(_ searches: [String], forKey key: String) {
        set(searches, forKey: key)
        synchronize()
    }

    func loadRecentSearches(forKey key: String) -> [String] {
        return array(forKey: key) as? [String] ?? []
    }
}

    // MARK: - Data Models
struct TransitRoute: Identifiable, Codable {
    let id: String
    let companyInnerId: String
    let routeNumber: String
    let startPoint: String
    let endPoint: String
    let stops: [String]
    let eta: String
    let isAccessible: Bool
    let mode: String
}

struct Vehicle: Identifiable, Codable {
    let id: String
    let type: String
    let routeInnerId: String
    let currentLocation: CLLocationCoordinate2D?
    let eta: String

    enum CodingKeys: String, CodingKey {
        case id, type
        case routeInnerId = "routeId"
        case eta, latitude, longitude
    }

    init(id: String, type: String, routeInnerId: String, currentLocation: CLLocationCoordinate2D?, eta: String) {
        self.id = id
        self.type = type
        self.routeInnerId = routeInnerId
        self.currentLocation = currentLocation
        self.eta = eta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        routeInnerId = try container.decode(String.self, forKey: .routeInnerId)
        eta = try container.decode(String.self, forKey: .eta)

        if let lat = try? container.decodeIfPresent(Double.self, forKey: .latitude),
           let lon = try? container.decodeIfPresent(Double.self, forKey: .longitude) {
            currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            currentLocation = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(routeInnerId, forKey: .routeInnerId)
        try container.encode(eta, forKey: .eta)
        if let location = currentLocation {
            try container.encode(location.latitude, forKey: .latitude)
            try container.encode(location.longitude, forKey: .longitude)
        }
    }
}

struct TransitNotification: Identifiable, Codable {
    let id: String
    let message: String
    let type: String
    let timestamp: Date
}

struct StopResponse: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let stopId: String
    let nameEn: String
    let lat: Double
    let long: Double

    enum CodingKeys: String, CodingKey {
        case stopId, nameEn, lat, long
    }

    init(stopId: String, nameEn: String, lat: Double, long: Double) {
        self.id = stopId
        self.stopId = stopId
        self.nameEn = nameEn
        self.lat = lat
        self.long = long
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stopId = try container.decode(String.self, forKey: .stopId)
        self.nameEn = try container.decode(String.self, forKey: .nameEn)
        self.lat = try container.decode(Double.self, forKey: .lat)
        self.long = try container.decode(Double.self, forKey: .long)
        self.id = stopId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stopId, forKey: .stopId)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(lat, forKey: .lat)
        try container.encode(long, forKey: .long)
    }

    static func ==(lhs: StopResponse, rhs: StopResponse) -> Bool {
        return lhs.stopId == rhs.stopId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stopId)
    }
}

    // MARK: - API Response Models
struct RouteFareResponse: Codable {
    let routes: [String: RouteInfo]?
    let holidays: [String]?
    struct RouteInfo: Codable {
        let fares: [Double]
        let company: String
        let routeNo: String
        let origEn: String
        let destEn: String
        let bound: String
        let stops: [String]
        let isAccessible: Bool
        let mode: String
    }
}

struct KMBStopResponse: Codable {
    let type: String?
    let version: String?
    let generatedTimestamp: String?
    let data: [KMBStop]?
    let stops: [KMBStop]?
    struct KMBStop: Codable {
        let stop: String
        let nameEn: String
        let lat: Double
        let long: Double
        enum CodingKeys: String, CodingKey {
            case stop
            case nameEn = "name_en"
            case lat
            case long
        }
    }
}

struct CTBStopResponse: Codable {
    let data: CTBStop
    struct CTBStop: Codable {
        let stop: String
        let nameEn: String
        let lat: String
        let long: String
        enum CodingKeys: String, CodingKey {
            case stop
            case nameEn = "name_en"
            case lat
            case long
        }
    }
}

struct NLBStopResponse: Codable {
    let stops: [NLBStop]?
    let data: [NLBStop]?
    struct NLBStop: Codable {
        let stopId: String
        let stopNameEn: String
        let lat: String
        let long: String
        enum CodingKeys: String, CodingKey {
            case stopId
            case stopNameEn = "stopName_e"
            case lat = "latitude"
            case long = "longitude"
        }
    }
}

struct MTRGeolocationResponse: Codable {
    let features: [Feature]?
    let error: String?
    struct Feature: Codable {
        let properties: Properties?
        let geometry: Geometry?
        struct Properties: Codable {
            let name: String?
            let address: String?
            let category: String?
            let dataset: String?
        }
        struct Geometry: Codable {
            let type: String?
            let coordinates: [Double]?
        }
    }
}

struct KMBETAResponse: Codable {
    let type: String?
    let version: String?
    let generatedTimestamp: String?
    let data: [KMBETA]
    struct KMBETA: Codable {
        let eta: String?
        let remarkEn: String?
        let lat: Double?
        let long: Double?
        enum CodingKeys: String, CodingKey {
            case eta
            case remarkEn = "remark_en"
            case lat
            case long
        }
    }
}

struct CTBETAResponse: Codable {
    let data: [CTBETA]
    struct CTBETA: Codable {
        let eta: String?
        let remarkEn: String?
        let lat: Double?
        let long: Double?
        enum CodingKeys: String, CodingKey {
            case eta
            case remarkEn = "rmk_en"
            case lat
            case long
        }
    }
}

struct GMBETAResponse: Codable {
    let data: [GMBETA]?
    struct GMBETA: Codable {
        let eta: String?
        let remarkEn: String?
        let lat: Double?
        let long: Double?
        enum CodingKeys: String, CodingKey {
            case eta
            case remarkEn = "remark_en"
            case lat
            case long
        }
    }
}

struct NLBETAResponse: Codable {
    let estimatedArrivals: [NLBETA]?
    struct NLBETA: Codable {
        let estimatedArrivalTime: String?
        let routeId: String
        let lat: String?
        let long: String?
        enum CodingKeys: String, CodingKey {
            case estimatedArrivalTime = "estimated_arrival_time"
            case routeId
            case lat
            case long
        }
    }
}

struct MTRScheduleResponse: Codable {
    let status: Int?
    let message: String?
    let data: [String: MTRLineData]
    struct MTRLineData: Codable {
        let up: [MTRSchedule]?
        let down: [MTRSchedule]?
        enum CodingKeys: String, CodingKey {
            case up = "UP"
            case down = "DOWN"
        }
    }
    struct MTRSchedule: Codable {
        let time: String
        let dest: String
    }
}

struct LightRailScheduleResponse: Codable {
    let platformList: [Platform]?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case platformList = "platform_list"
        case error
    }
    struct Platform: Codable {
        let routeList: [Train]?
        enum CodingKeys: String, CodingKey {
            case routeList = "route_list"
        }
    }
    struct Train: Codable {
        let time: String?
        let destEn: String?
        enum CodingKeys: String, CodingKey {
            case time = "time_en"
            case destEn = "dest_en"
        }
    }
}

    // MARK: - Core Data Entity
@objc(CachedStop)
class CachedStop: NSManagedObject {
    @NSManaged var stopId: String?
    @NSManaged var nameEn: String?
    @NSManaged var latitude: NSNumber?
    @NSManaged var longitude: NSNumber?
}

    // MARK: - Transit Service
class TransitService: ObservableObject, APIClient {
    @Published var routes: [TransitRoute] = []
    @Published var vehicles: [Vehicle] = []
    @Published var notifications: [TransitNotification] = []
    @Published var error: Error?
    @Published var isLoading: Bool = false
    @Published var stops: [StopResponse] = []
    private var timer: Timer?

    init() {
        loadCachedData()
        Task {
            await fetchStops()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchVehicleLocations()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func fetch<T: Codable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.init(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logError(error, url: url, data: data, context: "fetch")
            throw error
        }
    }

    func findNearbyStops(location: CLLocationCoordinate2D, maxDistance: Double = 1.0) -> [StopResponse] {
        stops.filter { stop in
            let stopLocation = CLLocation(latitude: stop.lat, longitude: stop.long)
            let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let distance = stopLocation.distance(from: userLocation) / 1000 // Convert to km
            return distance <= maxDistance
        }.sorted { stop1, stop2 in
            let loc1 = CLLocation(latitude: stop1.lat, longitude: stop1.long)
            let loc2 = CLLocation(latitude: stop2.lat, longitude: stop2.long)
            let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
            return loc1.distance(from: userLoc) < loc2.distance(from: userLoc)
        }
    }

    private func coordinates(latitude: String?, longitude: String?) -> CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              let latitude = Double(latitude), let longitude = Double(longitude) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func coordinates(latitude: Double?, longitude: Double?) -> CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func fetchStops() async {
        await loadCachedStops()
        var allStops: [StopResponse] = []

        do {
            if let kmbUrl = URL(string: "https://data.etabus.gov.hk/v1/transport/kmb/stop") {
                let response: KMBStopResponse = try await fetch(kmbUrl)
                let stops: [StopResponse] = (response.data ?? response.stops ?? []).map {
                    StopResponse(stopId: $0.stop, nameEn: $0.nameEn, lat: $0.lat, long: $0.long)
                }
                allStops.append(contentsOf: stops)
            } else {
                logError(URLError(.badURL), context: "fetchStops - Invalid KMB stop URL")
            }
        } catch {
            logError(error, context: "fetchStops - KMB")
        }

        do {
            if let ctbUrl = URL(string: "https://rt.data.gov.hk/v2/transport/citybus/stop/001007") {
                let response: CTBStopResponse = try await fetch(ctbUrl)
                guard let latitude = Double(response.data.lat),
                      let longitude = Double(response.data.long) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Citybus returned invalid coordinates"))
                }
                let stop = StopResponse(stopId: response.data.stop, nameEn: response.data.nameEn, lat: latitude, long: longitude)
                allStops.append(stop)
            } else {
                logError(URLError(.badURL), context: "fetchStops - Invalid CTB stop URL")
            }
        } catch {
            logError(error, context: "fetchStops - Citybus")
        }

        do {
            if let nlbUrl = URL(string: "https://rt.data.gov.hk/v2/transport/nlb/stop.php?action=list&routeId=1A") {
                let response: NLBStopResponse = try await fetch(nlbUrl)
                let stops: [StopResponse] = (response.stops ?? response.data ?? []).compactMap {
                    guard let latitude = Double($0.lat), let longitude = Double($0.long) else { return nil }
                    return StopResponse(stopId: $0.stopId, nameEn: $0.stopNameEn, lat: latitude, long: longitude)
                }
                allStops.append(contentsOf: stops)
            } else {
                logError(URLError(.badURL), context: "fetchStops - Invalid NLB stop URL")
            }
        } catch {
            logError(error, context: "fetchStops - NLB")
        }

        await MainActor.run {
            let uniqueStops = Array(Set(allStops))
            self.stops = uniqueStops
            self.cacheStops(uniqueStops)
            print("Fetched stops: \(uniqueStops.map { $0.nameEn })")
        }
    }

    func fetchRoutes(from origin: String, to destination: String, accessibleOnly: Bool = false) async {
        await MainActor.run {
            self.isLoading = true
            self.routes.removeAll()
        }

        guard let url = URL(string: "https://data.hkbus.app/routeFareList.min.json") else {
            logError(URLError(.badURL), context: "fetchRoutes - Invalid routeFareList URL")
            await loadCachedRoutes()
            await MainActor.run { self.isLoading = false }
            return
        }

        do {
            let response: RouteFareResponse = try await fetch(url)
            let filteredRoutes = response.routes?.values
                .filter {
                    $0.origEn.lowercased().contains(origin.lowercased()) &&
                    $0.destEn.lowercased().contains(destination.lowercased())
                }
                .map { route in
                    TransitRoute(
                        id: "\(route.company)+\(route.routeNo)",
                        companyInnerId: route.company,
                        routeNumber: route.routeNo,
                        startPoint: route.origEn,
                        endPoint: route.destEn,
                        stops: route.stops,
                        eta: "N/A",
                        isAccessible: route.isAccessible,
                        mode: route.mode
                    )
                } ?? []
            let routes = accessibleOnly ? filteredRoutes.filter { $0.isAccessible } : filteredRoutes
            await MainActor.run {
                self.routes.append(contentsOf: routes)
                self.cacheRoutes(routes)
                self.isLoading = false
            }
        } catch {
            logError(error, url: url, context: "fetchRoutes")
            await loadCachedRoutes()
            await MainActor.run { self.isLoading = false }
        }
    }

    func fetchVehicleLocations() async {
        await MainActor.run {
            self.isLoading = true
            self.vehicles.removeAll()
        }

        let companies = ["KMB", "CTB", "NWFB", "GMB", "NLB", "MTR", "LightRail"]
        var allVehicles: [Vehicle] = []

        for company in companies {
            do {
                let vehicles: [Vehicle] = try await fetchETAForCompany(company: company)
                allVehicles.append(contentsOf: vehicles)
            } catch {
                logError(error, context: "fetchVehicleLocations \(company)")
            }
        }

        await MainActor.run {
            self.vehicles.append(contentsOf: allVehicles)
            self.cacheVehicles(allVehicles)
            self.isLoading = false
            if self.vehicles.isEmpty {
                Task { await self.loadCachedVehicles() }
            }
        }
    }

    private func fetchETAForCompany(company: String) async throws -> [Vehicle] {
        guard let routeListURL = URL(string: "https://data.hkbus.app/routeFareList.min.json") else {
            throw URLError(.badURL)
        }

        let routeResponse: RouteFareResponse = try await fetch(routeListURL)
        let routes = routeResponse.routes?.values
            .filter { $0.company == company || (company == "LightRail" && $0.mode == "LightRail") || (company == "MTR" && $0.mode == "MTR") } ?? []
        let stops = routes.flatMap { $0.stops }.filter { !$0.isEmpty }
        let stopIds = Array(Set(stops))

        var vehicles: [Vehicle] = []

        for stopId in stopIds {
            do {
                switch company {
                    case "KMB":
                        if let url = URL(string: "https://data.etabus.gov.hk/v1/transport/kmb/eta/\(stopId)/1A/1") {
                            let etaResponse: KMBETAResponse = try await fetch(url)
                            let kmbVehicles: [Vehicle] = etaResponse.data.map { eta in
                                let location = coordinates(latitude: eta.lat, longitude: eta.long)
                                return Vehicle(
                                    id: "KMB-\(stopId)-\(eta.eta ?? "")",
                                    type: "Bus",
                                    routeInnerId: "1A",
                                    currentLocation: location,
                                    eta: eta.eta ?? "N/A"
                                )
                            }
                            vehicles.append(contentsOf: kmbVehicles)
                        }

                    case "CTB", "NWFB":
                        if let url = URL(string: "https://rt.data.gov.hk/v2/transport/citybus/eta/\(company)/\(stopId)/5B") {
                            let etaResponse: CTBETAResponse = try await fetch(url)
                            let ctbVehicles: [Vehicle] = etaResponse.data.map { eta in
                                let location = coordinates(latitude: eta.lat, longitude: eta.long)
                                return Vehicle(
                                    id: "\(company)-\(stopId)-\(eta.eta ?? "")",
                                    type: "Bus",
                                    routeInnerId: "5B",
                                    currentLocation: location,
                                    eta: eta.eta ?? "N/A"
                                )
                            }
                            vehicles.append(contentsOf: ctbVehicles)
                        }

                    case "GMB":
                        // No GMB ETA endpoint is available for the route data source used here.
                        break

                    case "NLB":
                        if let url = URL(string: "https://rt.data.gov.hk/v1/transport/nlb/stop.php?action=estimatedArrivals") {
                            let body: [String: String] = ["routeId": "1A", "stopId": stopId, "language": "en"]
                            var request = URLRequest(url: url)
                            request.httpMethod = "POST"
                            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                            request.httpBody = body
                                .map { key, value in
                                    let encodedValue = String(describing: value).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    return "\(key)=\(encodedValue)"
                                }
                                .joined(separator: "&")
                                .data(using: .utf8)
                            let (data, response) = try await URLSession.shared.data(for: request)
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                throw URLError(.init(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1))
                            }
                            let etaResponse = try JSONDecoder().decode(NLBETAResponse.self, from: data)
                            let nlbVehicles: [Vehicle] = etaResponse.estimatedArrivals?.map { eta in
                                let location = coordinates(latitude: eta.lat, longitude: eta.long)
                                return Vehicle(
                                    id: "NLB-\(stopId)-\(eta.estimatedArrivalTime ?? "")",
                                    type: "Bus",
                                    routeInnerId: eta.routeId,
                                    currentLocation: location,
                                    eta: eta.estimatedArrivalTime ?? "N/A"
                                )
                            } ?? []
                            vehicles.append(contentsOf: nlbVehicles)
                        }

                    case "MTR":
                        if let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=TCL&sta=\(stopId)") {
                            let scheduleResponse: MTRScheduleResponse = try await fetch(url)
                            let schedules = (scheduleResponse.data["TCL-\(stopId)"]?.up ?? []) + (scheduleResponse.data["TCL-\(stopId)"]?.down ?? [])
                            let mtrVehicles: [Vehicle] = schedules.map { schedule in
                                Vehicle(
                                    id: "MTR-\(stopId)-\(schedule.time)",
                                    type: "Train",
                                    routeInnerId: "TCL",
                                    currentLocation: nil,
                                    eta: schedule.time
                                )
                            }
                            vehicles.append(contentsOf: mtrVehicles)
                        }

                    case "LightRail":
                        if let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/lrt/getSchedule?station_id=\(stopId)") {
                            let scheduleResponse: LightRailScheduleResponse = try await fetch(url)
                            let lrVehicles: [Vehicle] = scheduleResponse.platformList?.flatMap { $0.routeList ?? [] }.map { train in
                                Vehicle(
                                    id: "LightRail-\(stopId)-\(train.time ?? "")",
                                    type: "Light Rail",
                                    routeInnerId: train.destEn ?? "Unknown",
                                    currentLocation: nil,
                                    eta: train.time ?? "N/A"
                                )
                            } ?? []
                            vehicles.append(contentsOf: lrVehicles)
                        }

                    default:
                        break
                }
            } catch {
                logError(error, context: "fetchETAForCompany \(company) stop \(stopId)")
            }
        }

        return vehicles
    }

    func fetchGeolocation(query: String) async -> [String] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geodata.gov.hk/gs/api/v1.0.0/locationSearch?q=\(encodedQuery)") else {
            logError(URLError(.badURL), context: "fetchGeolocation - Invalid URL")
            return []
        }

        do {
            let response: MTRGeolocationResponse = try await fetch(url)
            return response.features?.compactMap { $0.properties?.name } ?? []
        } catch {
            logError(error, url: url, context: "fetchGeolocation")
            return []
        }
    }

    func logError(_ error: Error, url: URL? = nil, data: Data? = nil, context: String) {
        if let urlError = error as? URLError {
            let urlString = url?.absoluteString ?? "unknown URL"
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no response body"
            print("API Error in \(context): Code \(urlError.code.rawValue), \(urlError.localizedDescription), URL: \(urlString), Response: \(responseBody.prefix(500))")
            self.error = urlError
        } else {
            let urlString = url?.absoluteString ?? "unknown URL"
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no response body"
            print("Error in \(context): \(error.localizedDescription), URL: \(urlString), Response: \(responseBody.prefix(500))")
            self.error = error
        }
    }

    private let cacheEncryptionKey = SymmetricKey(size: .bits256)

    private func encryptForCache(_ value: String) -> String? {
        guard let plaintext = value.data(using: .utf8) else { return nil }
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: cacheEncryptionKey)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            return nil
        }
    }

    private func cacheRoutes(_ routes: [TransitRoute]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                for route in routes {
                    let routeEntity = NSEntityDescription.insertNewObject(forEntityName: "CachedRoute", into: context)
                    routeEntity.setValue(route.id, forKey: "id")
                    routeEntity.setValue(route.companyInnerId, forKey: "companyInnerId")
                    routeEntity.setValue(route.routeNumber, forKey: "routeNumber")
                    routeEntity.setValue(route.startPoint, forKey: "startPoint")
                    routeEntity.setValue(route.endPoint, forKey: "endPoint")
                    routeEntity.setValue(route.stops, forKey: "stops")
                    routeEntity.setValue(route.eta, forKey: "eta")
                    routeEntity.setValue(route.isAccessible, forKey: "isAccessible")
                    routeEntity.setValue(route.mode, forKey: "mode")
                }
                try context.save()
            } catch {
                DispatchQueue.main.async { self.logError(error, context: "cacheRoutes") }
            }
        }
    }

    private func roundedCoordinate(_ value: Double?, decimals: Int = 3) -> Double? {
        guard let value = value else { return nil }
        let multiplier = pow(10.0, Double(decimals))
        return (value * multiplier).rounded() / multiplier
    }

    private func cacheVehicles(_ vehicles: [Vehicle]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                for vehicle in vehicles {
                    let vehicleEntity = NSEntityDescription.insertNewObject(forEntityName: "CachedVehicle", into: context)
                    vehicleEntity.setValue(vehicle.id, forKey: "id")
                    vehicleEntity.setValue(vehicle.type, forKey: "type")
                    vehicleEntity.setValue(vehicle.routeInnerId, forKey: "routeInnerId")
                    vehicleEntity.setValue(vehicle.eta, forKey: "eta")
                    let encryptedLatitude = vehicle.currentLocation?.latitude.flatMap { self.encryptForCache(String($0)) }
                    let encryptedLongitude = vehicle.currentLocation?.longitude.flatMap { self.encryptForCache(String($0)) }
                    vehicleEntity.setValue(encryptedLatitude, forKey: "latitude")
                    vehicleEntity.setValue(encryptedLongitude, forKey: "longitude")
                    vehicleEntity.setValue(self.roundedCoordinate(vehicle.currentLocation?.latitude), forKey: "latitude")
                    vehicleEntity.setValue(self.roundedCoordinate(vehicle.currentLocation?.longitude), forKey: "longitude")
                }
                try context.save()
            } catch {
                DispatchQueue.main.async { self.logError(error, context: "cacheVehicles") }
            }
        }
    }

    private func cacheStops(_ stops: [StopResponse]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                for stop in stops {
                    let stopEntity = NSEntityDescription.insertNewObject(forEntityName: "CachedStop", into: context)
                    stopEntity.setValue(stop.stopId, forKey: "stopId")
                    stopEntity.setValue(stop.nameEn, forKey: "nameEn")
                    stopEntity.setValue(stop.lat, forKey: "latitude")
                    stopEntity.setValue(stop.long, forKey: "longitude")
                }
                try context.save()
            } catch {
                DispatchQueue.main.async { self.logError(error, context: "cacheStops") }
            }
        }
    }

    private func loadCachedRoutes() async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "CachedRoute")
        do {
            let cachedRoutes: [NSManagedObject] = try await context.perform { () -> [NSManagedObject] in
                return try context.fetch(fetchRequest)
            }
            let routes = cachedRoutes.compactMap { entity -> TransitRoute? in
                guard let id = entity.value(forKey: "id") as? String,
                      let companyInnerId = entity.value(forKey: "companyInnerId") as? String,
                      let routeNumber = entity.value(forKey: "routeNumber") as? String,
                      let startPoint = entity.value(forKey: "startPoint") as? String,
                      let endPoint = entity.value(forKey: "endPoint") as? String,
                      let eta = entity.value(forKey: "eta") as? String,
                      let mode = entity.value(forKey: "mode") as? String else {
                    return nil
                }
                let stops = entity.value(forKey: "stops") as? [String] ?? []
                let isAccessible = entity.value(forKey: "isAccessible") as? Bool ?? false
                return TransitRoute(
                    id: id,
                    companyInnerId: companyInnerId,
                    routeNumber: routeNumber,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    stops: stops,
                    eta: eta,
                    isAccessible: isAccessible,
                    mode: mode
                )
            }
            await MainActor.run {
                self.routes = routes
            }
        } catch {
            await MainActor.run {
                self.logError(error, context: "loadCachedRoutes")
            }
        }
    }

    private func loadCachedVehicles() async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "CachedVehicle")
        do {
            let cachedVehicles: [NSManagedObject] = try await context.perform { () -> [NSManagedObject] in
                return try context.fetch(fetchRequest)
            }
            let vehicles = cachedVehicles.compactMap { entity -> Vehicle? in
                guard let id = entity.value(forKey: "id") as? String,
                      let type = entity.value(forKey: "type") as? String,
                      let routeInnerId = entity.value(forKey: "routeInnerId") as? String,
                      let eta = entity.value(forKey: "eta") as? String else {
                    return nil
                }
                let lat = entity.value(forKey: "latitude") as? Double
                let lon = entity.value(forKey: "longitude") as? Double
                let location = (lat != nil && lon != nil) ? CLLocationCoordinate2D(latitude: lat!, longitude: lon!) : nil
                return Vehicle(
                    id: id,
                    type: type,
                    routeInnerId: routeInnerId,
                    currentLocation: location,
                    eta: eta
                )
            }
            await MainActor.run {
                self.vehicles = vehicles
            }
        } catch {
            await MainActor.run {
                self.logError(error, context: "loadCachedVehicles")
            }
        }
    }

    private func loadCachedStops() async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<CachedStop>(entityName: "CachedStop")
        do {
            let cachedStops: [CachedStop] = try await context.perform { () -> [CachedStop] in
                return try context.fetch(fetchRequest)
            }
            let stops = cachedStops.compactMap { entity -> StopResponse? in
                guard let stopId = entity.stopId,
                      let nameEn = entity.nameEn,
                      let lat = entity.latitude as? Double,
                      let lon = entity.longitude as? Double else {
                    return nil
                }
                return StopResponse(stopId: stopId, nameEn: nameEn, lat: lat, long: lon)
            }
            await MainActor.run {
                self.stops = stops
                print("Loaded cached stops: \(stops.map { $0.nameEn })")
            }
        } catch {
            await MainActor.run {
                self.logError(error, context: "loadCachedStops")
            }
        }
    }
    
    private func loadCachedData() {
        Task {
            await loadCachedRoutes()
            await loadCachedVehicles()
            await loadCachedStops()
        }
    }
}

    // MARK: - Core Data Persistence
class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "TransitModel")
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

    // MARK: - User Preferences
class UserPreferences: ObservableObject {
    @Published var language: String = "en"
    @Published var highContrastMode: Bool = false
    @Published var audioNavigation: Bool = false
    @Published var favoriteRoutes: [String] = []
    @Published var notificationPreferences: [String: Bool] = ["delays": true, "disruptions": true]
}

    // MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var userLocation: CLLocationCoordinate2D?

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdatingLocation()
        }
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdatingLocation()
            case .denied, .restricted:
                userLocation = nil
            case .notDetermined:
                break
            @unknown default:
                break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            userLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

    // MARK: - View Modifier for Accessibility
struct AccessibilityModifier: ViewModifier {
    let label: String
    let hint: String?

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
}

extension View {
    func accessibility(label: String, hint: String? = nil) -> some View {
        modifier(AccessibilityModifier(label: label, hint: hint))
    }
}

    // MARK: - Map Container View
struct MapContainerView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let vehicles: [Vehicle]
    let stops: [StopResponse]
    @Binding var selectedVehicle: Vehicle?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: true)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)

            // Remove existing annotations
        uiView.removeAnnotations(uiView.annotations)

            // Add stop annotations
        let stopAnnotations = stops.map { stop -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.long)
            annotation.title = stop.nameEn
            annotation.subtitle = "Stop ID: \(stop.stopId)"
            return annotation
        }

            // Add vehicle annotations
        let vehicleAnnotations = vehicles.compactMap { vehicle -> MKPointAnnotation? in
            guard let location = vehicle.currentLocation else { return nil }
            let annotation = MKPointAnnotation()
            annotation.coordinate = location
            annotation.title = "\(vehicle.type) - Route \(vehicle.routeInnerId)"
            annotation.subtitle = "ETA: \(vehicle.eta)"
            return annotation
        }

        uiView.addAnnotations(stopAnnotations + vehicleAnnotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView

        init(_ parent: MapContainerView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "TransitAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                annotationView?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            } else {
                annotationView?.annotation = annotation
            }

            if annotation.title??.contains("Stop") ?? false {
                annotationView?.markerTintColor = .blue
            } else {
                annotationView?.markerTintColor = .red
            }

            return annotationView
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let subtitle = view.annotation?.subtitle, subtitle?.contains("ETA") ?? false,
               let title = view.annotation?.title, let vehicleId = title?.split(separator: "-").last {
                parent.selectedVehicle = parent.vehicles.first { $0.id.contains(String(vehicleId)) }
            }
        }
    }
}

    // MARK: - Content View
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            RoutePlanningView()
                .tabItem { Label("Routes", systemImage: "map") }
            NotificationsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .navigationViewStyle(.stack)
        .environmentObject(TransitService())
        .environmentObject(UserPreferences())
        .environmentObject(LocationManager())
    }
}

    // MARK: - Supporting Views
struct SuggestionView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Text(suggestion)
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                            .onTapGesture {
                                onSelect(suggestion)
                            }
                            .accessibility(label: "Suggestion: \(suggestion)", hint: "Tap to select this suggestion")
                    }
                }
            }
            .frame(maxHeight: 120)
            .background(Color(.systemBackground).opacity(0.95))
            .cornerRadius(10)
            .shadow(radius: 2)
            .padding(.top, 4)
        }
    }
}

struct OriginInputView: View {
    @Binding var origin: String
    @Binding var originSuggestions: [String]
    @Binding var isOriginFocused: Bool
    let updateSuggestions: () -> Void
    let onSelectSuggestion: (String) -> Void
    @FocusState private var focusedField: SearchField?

    var body: some View {
        VStack {
            TextField("Origin", text: $origin, onEditingChanged: { isEditing in
                isOriginFocused = isEditing
                focusedField = isEditing ? .origin : nil
                updateSuggestions()
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .focused($focusedField, equals: .origin)
            .accessibility(label: "Enter origin")
            .onChange(of: origin) { _ in
                updateSuggestions()
            }
            if focusedField == .origin && !originSuggestions.isEmpty {
                SuggestionView(suggestions: originSuggestions, onSelect: onSelectSuggestion)
                    .padding(.horizontal)
            }
        }
    }
}

struct DestinationInputView: View {
    @Binding var destination: String
    @Binding var destinationSuggestions: [String]
    @Binding var isDestinationFocused: Bool
    let updateSuggestions: () -> Void
    let onSelectSuggestion: (String) -> Void
    @FocusState private var focusedField: SearchField?

    var body: some View {
        VStack {
            TextField("Destination", text: $destination, onEditingChanged: { isEditing in
                isDestinationFocused = isEditing
                focusedField = isEditing ? .destination : nil
                updateSuggestions()
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .focused($focusedField, equals: .destination)
            .accessibility(label: "Enter destination")
            .onChange(of: destination) { _ in
                updateSuggestions()
            }
            if focusedField == .destination && !destinationSuggestions.isEmpty {
                SuggestionView(suggestions: destinationSuggestions, onSelect: onSelectSuggestion)
                    .padding(.horizontal)
            }
        }
    }
}

struct SearchControlsView: View {
    @Binding var showAccessibleOnly: Bool
    let searchAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Toggle("Wheelchair Accessible Only", isOn: $showAccessibleOnly)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibility(label: "Toggle wheelchair accessible routes")

            Button(action: searchAction) {
                Text("Search Routes")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .accessibility(label: "Search routes button")
        }
    }
}

struct VehiclesListView: View {
    let vehicles: [Vehicle]
    @Binding var selectedVehicle: Vehicle?
    @Binding var region: MKCoordinateRegion

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(vehicles) { vehicle in
                    VehicleCardView(vehicle: vehicle, isSelected: vehicle.id == selectedVehicle?.id)
                        .onTapGesture {
                            selectedVehicle = vehicle
                            if let location = vehicle.currentLocation {
                                region.center = location
                                region.span = MKCoordinateSpan(latitudeDelta: 0.00225, longitudeDelta: 0.00245)
                            }
                        }
                        .accessibility(label: "\(vehicle.type) on Route \(vehicle.routeInnerId), ETA: \(vehicle.eta)", hint: "Tap to view on map")
                }
            }
            .padding(.horizontal)
        }
    }
}

struct MapAndVehiclesView: View {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedVehicle: Vehicle?
    let vehicles: [Vehicle]
    let stops: [StopResponse]
    let isLoading: Bool
    let error: Error?

    var body: some View {
        VStack {
            ZStack {
                MapContainerView(region: $region, vehicles: vehicles, stops: stops, selectedVehicle: $selectedVehicle)
                    .frame(height: 300)
                    .accessibility(label: "Map showing nearby transit vehicles and stops")
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground).opacity(0.8))
                        .cornerRadius(10)
                        .accessibility(label: "Loading transit data")
                }
            }
            Text("Nearby Transit")
                .font(.title2)
                .padding(.top)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            VehiclesListView(vehicles: vehicles, selectedVehicle: $selectedVehicle, region: $region)
            if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
                    .accessibility(label: "Error: \(error.localizedDescription)")
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var transitService: TransitService
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var locationManager: LocationManager
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var showAccessibleOnly: Bool = false
    @State private var selectedVehicle: Vehicle? = nil
    @State private var isGeocoding: Bool = false
    @State private var recentSearches: [String] = UserDefaults.standard.loadRecentSearches(forKey: "recentSearches")
    @State private var originSuggestions: [String] = []
    @State private var destinationSuggestions: [String] = []
    @State private var hasCenteredMap: Bool = false
    @State private var showLocationPermissionAlert: Bool = false
    @State private var isOriginFocused: Bool = false
    @State private var isDestinationFocused: Bool = false
    @FocusState private var focusedField: SearchField?

    private let defaultSuggestions = ["Jordan Road", "Tsuen Wan Station", "Central", "Mong Kok", "Kowloon Station"]

    var filteredVehicles: [Vehicle] {
        guard let userLocation = locationManager.userLocation else { return transitService.vehicles }
        return transitService.vehicles.filter { vehicle in
            guard let vehicleLocation = vehicle.currentLocation else { return false }
            let vehicleCLLocation = CLLocation(latitude: vehicleLocation.latitude, longitude: vehicleLocation.longitude)
            let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            return vehicleCLLocation.distance(from: userCLLocation) / 1000 <= 1.0 // 1 km radius
        }
    }

    var nearbyStops: [StopResponse] {
        guard let userLocation = locationManager.userLocation else { return [] }
        return transitService.findNearbyStops(location: userLocation)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 8) {
                    OriginInputView(
                        origin: $origin,
                        originSuggestions: $originSuggestions,
                        isOriginFocused: $isOriginFocused,
                        updateSuggestions: updateOriginSuggestions,
                        onSelectSuggestion: { suggestion in
                            origin = suggestion
                            updateRecentSearches(suggestion)
                            originSuggestions = []
                            focusedField = nil
                        }
                    )
                    DestinationInputView(
                        destination: $destination,
                        destinationSuggestions: $destinationSuggestions,
                        isDestinationFocused: $isDestinationFocused,
                        updateSuggestions: updateDestinationSuggestions,
                        onSelectSuggestion: { suggestion in
                            destination = suggestion
                            updateRecentSearches(suggestion)
                            destinationSuggestions = []
                            focusedField = nil
                        }
                    )
                    SearchControlsView(
                        showAccessibleOnly: $showAccessibleOnly,
                        searchAction: {
                            Task {
                                await transitService.fetchRoutes(from: origin, to: destination, accessibleOnly: showAccessibleOnly)
                            }
                            updateRecentSearches("\(origin) to \(destination)")
                        }
                    )
                    MapAndVehiclesView(
                        region: $region,
                        selectedVehicle: $selectedVehicle,
                        vehicles: filteredVehicles,
                        stops: nearbyStops,
                        isLoading: transitService.isLoading,
                        error: transitService.error
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Transit App")
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestLocationPermission()
                }
            }
            .onChange(of: locationManager.userLocation) { newLocation in
                if let location = newLocation, !hasCenteredMap {
                    region.center = location
                    hasCenteredMap = true
                }
            }
            .alert(isPresented: $showLocationPermissionAlert) {
                Alert(
                    title: Text("Location Access Required"),
                    message: Text("This app needs location access to show nearby transit options."),
                    primaryButton: .default(Text("Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func updateOriginSuggestions() {
        guard isOriginFocused else {
            originSuggestions = []
            return
        }
        let filteredRecents = recentSearches.filter { $0.lowercased().contains(origin.lowercased()) }
        if origin.isEmpty {
            originSuggestions = Array(filteredRecents.prefix(5)) + defaultSuggestions.filter { !filteredRecents.contains($0) }.prefix(5 - filteredRecents.count)
        } else {
            Task {
                let geolocationSuggestions = await transitService.fetchGeolocation(query: origin)
                await MainActor.run {
                    originSuggestions = Array(Set(filteredRecents + geolocationSuggestions).prefix(5))
                }
            }
        }
    }

    private func updateDestinationSuggestions() {
        guard isDestinationFocused else {
            destinationSuggestions = []
            return
        }
        let filteredRecents = recentSearches.filter { $0.lowercased().contains(destination.lowercased()) }
        if destination.isEmpty {
            destinationSuggestions = Array(filteredRecents.prefix(5)) + defaultSuggestions.filter { !filteredRecents.contains($0) }.prefix(5 - filteredRecents.count)
        } else {
            Task {
                let geolocationSuggestions = await transitService.fetchGeolocation(query: destination)
                await MainActor.run {
                    destinationSuggestions = Array(Set(filteredRecents + geolocationSuggestions).prefix(5))
                }
            }
        }
    }

    private func updateRecentSearches(_ search: String) {
        if !search.isEmpty && !recentSearches.contains(search) {
            recentSearches.insert(search, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
            UserDefaults.standard.saveRecentSearches(recentSearches, forKey: "recentSearches")
        }
    }
}

    // MARK: - Route Planning View
struct RoutePlanningView: View {
    @EnvironmentObject var transitService: TransitService
    @EnvironmentObject var userPreferences: UserPreferences

    var body: some View {
        NavigationView {
            List {
                ForEach(transitService.routes) { route in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route \(route.routeNumber) (\(route.companyInnerId))")
                            .font(.headline)
                        Text("From: \(route.startPoint)")
                        Text("To: \(route.endPoint)")
                        Text("ETA: \(route.eta)")
                        if route.isAccessible {
                            Text("Wheelchair Accessible")
                                .foregroundColor(.green)
                        }
                        Text("Mode: \(route.mode)")
                    }
                    .padding(.vertical, 4)
                    .accessibility(label: "Route \(route.routeNumber) from \(route.startPoint) to \(route.endPoint), ETA: \(route.eta), \(route.isAccessible ? "Wheelchair Accessible, " : "")Mode: \(route.mode)")
                }
            }
            .navigationTitle("Route Planning")
            .overlay {
                if transitService.isLoading {
                    ProgressView()
                        .accessibility(label: "Loading routes")
                }
            }
        }
    }
}

    // MARK: - Notifications View
struct NotificationsView: View {
    @EnvironmentObject var transitService: TransitService
    @EnvironmentObject var userPreferences: UserPreferences

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var filteredNotifications: [TransitNotification] {
        transitService.notifications.filter { notification in
            userPreferences.notificationPreferences[notification.type] ?? true
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredNotifications) { notification in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notification.message)
                            .font(.headline)
                        Text(notification.type.capitalized)
                            .foregroundColor(.gray)
                        Text(dateFormatter.string(from: notification.timestamp))
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .accessibilityLabel("\(notification.message), Type: \(notification.type), Date: \(dateFormatter.string(from: notification.timestamp))")
                }
            }
            .navigationTitle("Notifications")
        }
    }
}

    // MARK: - Profile View
struct ProfileView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @State private var languageSelection: String
    @State private var notificationSelections: [String: Bool]

    init() {
        let preferences = UserPreferences()
        _languageSelection = State(initialValue: preferences.language)
        _notificationSelections = State(initialValue: preferences.notificationPreferences)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Picker("Language", selection: $languageSelection) {
                        Text("English").tag("en")
                        Text("Chinese").tag("zh")
                    }
                    .accessibility(label: "Select language")
                    Toggle("High Contrast Mode", isOn: $userPreferences.highContrastMode)
                        .accessibility(label: "Toggle high contrast mode")
                    Toggle("Audio Navigation", isOn: $userPreferences.audioNavigation)
                        .accessibility(label: "Toggle audio navigation")
                }
                Section(header: Text("Notifications")) {
                    ForEach(notificationSelections.keys.sorted(), id: \.self) { key in
                        Toggle(key.capitalized, isOn: Binding(
                            get: { notificationSelections[key] ?? true },
                            set: { notificationSelections[key] = $0 }
                        ))
                        .accessibility(label: "Toggle \(key) notifications")
                    }
                }
                Section(header: Text("Favorite Routes")) {
                    ForEach(userPreferences.favoriteRoutes, id: \.self) { route in
                        Text(route)
                            .accessibility(label: "Favorite route: \(route)")
                    }
                    .onDelete { indices in
                        userPreferences.favoriteRoutes.remove(atOffsets: indices)
                    }
                }
            }
            .navigationTitle("Profile")
            .onChange(of: languageSelection) { newValue in
                userPreferences.language = newValue
            }
            .onChange(of: notificationSelections) { newValue in
                userPreferences.notificationPreferences = newValue
            }
        }
    }
}
    // MARK: - Vehicle Card View
struct VehicleCardView: View {
    let vehicle: Vehicle
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: vehicle.type.lowercased() == "bus" ? "bus" : "tram")
                .foregroundColor(isSelected ? .blue : .gray)
            VStack(alignment: .leading) {
                Text("Route \(vehicle.routeInnerId)")
                    .font(.headline)
                Text("ETA: \(vehicle.eta)")
                    .font(.subheadline)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: isSelected ? 2 : 0)
    }
}

    // MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(TransitService())
            .environmentObject(UserPreferences())
            .environmentObject(LocationManager())
    }
}
