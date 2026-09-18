# Hong Kong Transit

Hong Kong Transit is a SwiftUI app for tracking public transport in Hong Kong using live open-data feeds, local caching, and on-device location-aware stop discovery.

## What the app does

- Shows nearby stops on a map and ranks them by distance from the user's location.
- Displays next-arrival estimates for KMB, Citybus, NLB, and MTR feeds when the source payload is available.
- Maintains provider-level health checks so failed feeds are visible rather than silently hidden.
- Persists the last successful transit snapshot in SwiftData for offline fallback and quick startup.
- Keeps route, arrival, and alert data typed around provider-specific ingestion rather than a single one-size-fits-all schema.

## Current architecture

The app is intentionally split into a few core responsibilities:

- `TransitDomain.swift` defines the transport domain model: stops, routes, arrivals, feed status, and error semantics.
- `TransitAPI.swift` contains the feed catalog, HTTP client, adapter protocol, provider registry, and merge logic.
- `TransitRepository.swift` owns the runtime store: refresh orchestration, cache handling, nearby-stop filtering, and favorites persistence.
- `TransitViews.swift` renders the SwiftUI experience: map, routes, alerts, and settings flows.
- `LocationStore.swift` handles permission prompts and location updates.

The app prefers direct open-data access unless a future server-side normalizer is added through `TransitAggregationClient`.

## Data sources and privacy

The app reads public Hong Kong transport feeds from operator and government endpoints. It keeps only the last successful payload and does not embed API secrets in the client. Location is optional and remains on-device; it is used only to sort nearby stops and select the map center.

## Running the app

Open `TransitApp.xcodeproj` in Xcode and run the `TransitApp` scheme on an iOS Simulator or a connected device.

If you want to validate logic without launching the UI, use the Swift test target in Xcode or run:

```bash
xcodebuild -project TransitApp.xcodeproj -scheme TransitApp -destination 'platform=iOS Simulator,name=Any iOS Simulator Device' test
```

## Extending the catalog

`HongKongTransitCatalog` is the single source of truth for provider endpoints. Add a new feed there when introducing a new dataset or a new provider-specific adapter. Keep the payload contract explicit, and prefer per-provider decoding instead of collapsing all upstream feeds into a loosely typed dictionary.

## Related files

- `TransitApp/TransitAPI.swift`
- `TransitApp/TransitRepository.swift`
- `TransitApp/TransitDomain.swift`
- `TransitApp/TransitViews.swift`
- `TransitAppTests/TransitAppTests.swift`
