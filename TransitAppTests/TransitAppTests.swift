//
//  TransitAppTests.swift
//  TransitAppTests
//
//  Created by Henry Lam on 2/5/2025.
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import TransitApp

@MainActor
struct TransitAppTests {

    private struct StubProvider: TransitProvider {
        let providerID: String
        let endpoints: [TransitEndpoint]
        let snapshot: TransitSnapshot

        init(providerID: String = "Stub", snapshot: TransitSnapshot, endpoint: URL = URL(string: "https://example.com")!) {
            self.providerID = providerID
            self.snapshot = snapshot
            self.endpoints = [TransitEndpoint(id: providerID, provider: providerID, mode: .bus, purpose: "stub", url: endpoint, refreshInterval: 30)]
        }

        func fetchSnapshot(using client: TransitHTTPClient) async throws -> TransitSnapshot {
            snapshot
        }
    }

    @Test func snapshotMergeDeduplicatesStopsAndKeepsLatestTimestamp() {
        let stop = TransitStop(
            id: "KMB-1",
            name: "Central",
            coordinate: Coordinate(latitude: 22.28, longitude: 114.16),
            provider: "KMB"
        )
        let secondStop = TransitStop(
            id: "KMB-2",
            name: "Causeway Bay",
            coordinate: Coordinate(latitude: 22.28, longitude: 114.19),
            provider: "KMB"
        )
        let earlier = TransitSnapshot(stops: [stop], fetchedAt: Date(timeIntervalSince1970: 1))
        let later = TransitSnapshot(stops: [stop, secondStop], fetchedAt: Date(timeIntervalSince1970: 2))

        let merged = earlier.merged(with: later)

        #expect(merged.stops.count == 2)
        #expect(merged.fetchedAt == later.fetchedAt)
    }

    @Test func arrivalMinutesAreNeverNegative() {
        let arrival = Arrival(
            id: "arrival",
            routeID: "route",
            routeNumber: "1A",
            destination: "Central",
            mode: .bus,
            expectedAt: .now.addingTimeInterval(-60),
            status: nil,
            provider: "KMB",
            observedAt: .now
        )

        #expect(arrival.minutesAway == 0)
    }

    @Test func httpClientRejectsInvalidHttpResponses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.response = (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))

        let client = TransitHTTPClient(session: URLSession(configuration: config))

        do {
            _ = try await client.get(TransitSnapshot.self, from: URL(string: "https://example.com")!)
            Issue.record("Expected an invalid response error for a 500 status code.")
        } catch TransitError.invalidResponse {
            // expected
        }
    }

    @Test func transitStoreRefreshMergesAndPersistsIncomingData() async throws {
        let arrival = Arrival(
            id: "arrival-1",
            routeID: "route-1",
            routeNumber: "1A",
            destination: "Central",
            mode: .bus,
            expectedAt: .now.addingTimeInterval(600),
            status: nil,
            provider: "KMB",
            observedAt: .now
        )
        let snapshot = TransitSnapshot(stops: [TransitStop(id: "stop-1", name: "Central", coordinate: Coordinate(latitude: 22.28, longitude: 114.16), provider: "KMB")], arrivals: [arrival], fetchedAt: .now)
        let store = TransitStore(registry: TransitProviderRegistry(providers: [StubProvider(providerID: "KMB", snapshot: snapshot)]), client: TransitHTTPClient())
        let container = try ModelContainer(for: CachedTransitSnapshot.self, configurations: ModelConfiguration(isStoredInMemory: true))
        let context = ModelContext(container)

        store.attach(context: context)
        await store.refresh(force: true)

        #expect(store.snapshot.stops.count == 1)
        #expect(store.snapshot.arrivals.count == 1)
        #expect(store.lastError == nil)
        #expect(try context.fetch(FetchDescriptor<CachedTransitSnapshot>()).count == 1)
    }

    @Test func transitStoreFallsBackToCachedSnapshotWhenAllFeedsAreEmpty() async throws {
        let cachedStop = TransitStop(id: "stop-1", name: "Central", coordinate: Coordinate(latitude: 22.28, longitude: 114.16), provider: "KMB")
        let cachedSnapshot = TransitSnapshot(stops: [cachedStop], fetchedAt: .now)
        let container = try ModelContainer(for: CachedTransitSnapshot.self, configurations: ModelConfiguration(isStoredInMemory: true))
        let context = ModelContext(container)
        let saved = CachedTransitSnapshot(payload: try JSONEncoder.transit.encode(cachedSnapshot), fetchedAt: cachedSnapshot.fetchedAt)
        context.insert(saved)
        try context.save()

        let store = TransitStore(registry: TransitProviderRegistry(providers: [StubProvider(providerID: "KMB", snapshot: TransitSnapshot())]), client: TransitHTTPClient())
        store.attach(context: context)

        await store.refresh(force: true)

        #expect(store.lastError == "No transit feeds are reachable right now. Showing cached data when available.")
        #expect(store.snapshot.stops.count == 1)
    }

    @Test func nearbyStopsSortByDistanceAndHonorTheSearchRadius() async {
        let snapshot = TransitSnapshot(stops: [
            TransitStop(id: "near", name: "Near", coordinate: Coordinate(latitude: 22.281, longitude: 114.160), provider: "KMB"),
            TransitStop(id: "far", name: "Far", coordinate: Coordinate(latitude: 22.300, longitude: 114.180), provider: "KMB")
        ])
        let store = TransitStore(registry: TransitProviderRegistry(providers: [StubProvider(providerID: "KMB", snapshot: snapshot)]))
        let origin = CLLocationCoordinate2D(latitude: 22.28, longitude: 114.16)

        await store.refresh(force: true)

        let near = store.nearbyStops(around: origin, radius: 2_000)
        let withinOnly = store.nearbyStops(around: origin, radius: 200)

        #expect(near.first?.id == "near")
        #expect(withinOnly.count == 1)
        #expect(withinOnly.first?.id == "near")
    }
}

private final class MockURLProtocol: URLProtocol {
    static var response: (HTTPURLResponse, Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
