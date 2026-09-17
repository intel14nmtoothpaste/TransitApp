//
//  TransitAppTests.swift
//  TransitAppTests
//
//  Created by Henry Lam on 2/5/2025.
//

import Testing
@testable import TransitApp

struct TransitAppTests {

    @Test func snapshotMergeDeduplicatesStops() {
        let stop = TransitStop(
            id: "KMB-1",
            name: "Central",
            coordinate: Coordinate(latitude: 22.28, longitude: 114.16),
            provider: "KMB"
        )
        let first = TransitSnapshot(stops: [stop])
        let second = TransitSnapshot(stops: [stop])

        #expect(first.merged(with: second).stops.count == 1)
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

}
