import CoreLocation
import Combine
import Foundation
import SwiftData

/// Persisted cache for the last successful snapshot fetched from the network.
@Model
final class CachedTransitSnapshot {
    @Attribute(.unique) var id: String
    var payload: Data
    var fetchedAt: Date

    init(id: String = "hong-kong", payload: Data = Data(), fetchedAt: Date = .distantPast) {
        self.id = id
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// Runtime coordinator for transit refreshes, provider health, and cached fallback behavior.
@MainActor
final class TransitStore: ObservableObject {
    @Published private(set) var snapshot = TransitSnapshot()
    @Published private(set) var feedStatuses: [FeedStatus] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var dataHealth: FeedHealth = .unknown
    @Published private(set) var consecutiveRefreshFailures = 0
    @Published var lastError: String?

    private let registry: TransitProviderRegistry
    private let client: TransitHTTPClient
    private var modelContext: ModelContext?
    private var refreshTask: Task<Void, Never>?

    init(registry: TransitProviderRegistry = TransitProviderRegistry(), client: TransitHTTPClient = TransitHTTPClient()) {
        self.registry = registry
        self.client = client
    }

    /// Connects the store to SwiftData so a cached snapshot can be restored on startup.
    func attach(context: ModelContext) {
        modelContext = context
        loadCache()
    }

    /// Fetches fresh provider payloads and merges them into the current snapshot.
    ///
    /// If a refresh returns an empty result, the store preserves the last successful payload and
    /// records a user-visible error instead of silently dropping the existing data.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, snapshot.fetchedAt.timeIntervalSinceNow > -20 { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Keep one refresh in flight at a time and never overwrite the last known-good state
        // with an empty provider result unless all feeds are actually unavailable.
        let result = await registry.fetchAll(using: client)
        let incoming = result.0
        feedStatuses = result.1
        if incoming.stops.isEmpty && incoming.routes.isEmpty && incoming.arrivals.isEmpty && incoming.alerts.isEmpty {
            consecutiveRefreshFailures += 1
            dataHealth = .unavailable
            lastError = result.1.compactMap(\.message).joined(separator: " ")
            if lastError?.isEmpty == true {
                lastError = "No transit feeds are reachable right now. Showing cached data when available."
            }
            return
        }
        if !incoming.stops.isEmpty || !incoming.routes.isEmpty || !incoming.arrivals.isEmpty || !incoming.alerts.isEmpty {
            snapshot = snapshot.merged(with: incoming)
            snapshot.fetchedAt = .now
            consecutiveRefreshFailures = 0
        }
        let unavailable = feedStatuses.filter { !$0.isAvailable }
        dataHealth = unavailable.isEmpty ? .healthy : (snapshot.fetchedAt.timeIntervalSinceNow < -300 ? .stale : .healthy)
        lastError = unavailable.compactMap(\.message).joined(separator: " ").nilIfEmpty
        saveCache()
    }

    /// Starts a periodic polling loop that backs off exponentially when providers fail.
    func startLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let failures = self?.consecutiveRefreshFailures ?? 0
                let delay = min(300, 30 * pow(2, Double(failures)))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stopLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Returns stops within a radius of a coordinate, sorted by proximity.
    func nearbyStops(around coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 1_500) -> [TransitStop] {
        guard radius > 0 else { return [] }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearby = snapshot.stops.reduce(into: [(stop: TransitStop, distance: CLLocationDistance)]()) { partial, stop in
            let stopLocation = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
            let distance = origin.distance(from: stopLocation)
            guard distance <= radius else { return }
            partial.append((stop, distance))
        }

        return nearby
            .sorted { $0.distance < $1.distance }
            .map(\.stop)
    }

    private func loadCache() {
        guard let modelContext else { return }
        guard let cached = try? modelContext.fetch(FetchDescriptor<CachedTransitSnapshot>()).first,
              let decoded = try? JSONDecoder.transit.decode(TransitSnapshot.self, from: cached.payload) else { return }
        snapshot = decoded
    }

    private func saveCache() {
        guard let modelContext,
              let payload = try? JSONEncoder.transit.encode(snapshot) else { return }
        if let existing = try? modelContext.fetch(FetchDescriptor<CachedTransitSnapshot>()).first {
            existing.payload = payload
            existing.fetchedAt = snapshot.fetchedAt
        } else {
            modelContext.insert(CachedTransitSnapshot(payload: payload, fetchedAt: snapshot.fetchedAt))
        }
        do {
            try modelContext.save()
        } catch {
            lastError = "Transit data refreshed, but could not be saved locally: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension JSONEncoder {
    static var transit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Maintains the user's persisted set of favorite stops and routes.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var stopIDs: Set<String>
    @Published private(set) var routeIDs: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stopIDs = Set(defaults.stringArray(forKey: "favoriteStopIDs") ?? [])
        routeIDs = Set(defaults.stringArray(forKey: "favoriteRouteIDs") ?? [])
    }

    /// Toggles a stop in the persisted favorites list.
    func toggleStop(_ id: String) {
        stopIDs.toggleMembership(of: id)
        defaults.set(Array(stopIDs), forKey: "favoriteStopIDs")
    }

    /// Toggles a route in the persisted favorites list.
    func toggleRoute(_ id: String) {
        routeIDs.toggleMembership(of: id)
        defaults.set(Array(routeIDs), forKey: "favoriteRouteIDs")
    }
}

private extension Set where Element == String {
    mutating func toggleMembership(of value: String) {
        if contains(value) { remove(value) } else { insert(value) }
    }
}
