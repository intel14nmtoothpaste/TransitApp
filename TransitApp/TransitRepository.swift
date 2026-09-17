import CoreLocation
import Combine
import Foundation
import SwiftData

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

@MainActor
final class TransitStore: ObservableObject {
    @Published private(set) var snapshot = TransitSnapshot()
    @Published private(set) var feedStatuses: [FeedStatus] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private let registry = TransitProviderRegistry()
    private let client = TransitHTTPClient()
    private var modelContext: ModelContext?
    private var refreshTask: Task<Void, Never>?

    func attach(context: ModelContext) {
        modelContext = context
        loadCache()
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, snapshot.fetchedAt.timeIntervalSinceNow > -20 { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await registry.fetchAll(using: client)
        let incoming = result.0
        feedStatuses = result.1
        if incoming.stops.isEmpty && incoming.arrivals.isEmpty && snapshot.stops.isEmpty {
            lastError = "No transit feeds are reachable right now. Showing cached data when available."
            return
        }
        snapshot = snapshot.merged(with: incoming)
        snapshot.fetchedAt = .now
        lastError = feedStatuses.first(where: { !$0.isAvailable })?.message
        saveCache()
    }

    func startLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopLiveUpdates() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func nearbyStops(around coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 1_500) -> [TransitStop] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return snapshot.stops
            .sorted { first, second in
                origin.distance(from: CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)) <
                origin.distance(from: CLLocation(latitude: second.coordinate.latitude, longitude: second.coordinate.longitude))
            }
            .filter {
                origin.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <= radius
            }
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
        try? modelContext.save()
    }
}

extension JSONEncoder {
    static var transit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
