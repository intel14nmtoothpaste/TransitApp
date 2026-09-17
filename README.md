# Hong Kong Transit

An Apple-native Hong Kong public transport app built with SwiftUI, MapKit, Core Location, Swift concurrency, and SwiftData.

## Product foundation

- Map-first nearby stop discovery for iPhone, iPad, and Mac Catalyst.
- Live refresh orchestration with explicit feed health and offline cache fallback.
- Typed provider registry for KMB, Citybus, NLB, MTR/LRT, geodata search, and shared route metadata.
- Route, arrival, alert, accessibility, and provider-provenance domain models ready for additional data.gov.hk feeds.
- Direct open-data calls by default, with `TransitAggregationClient` as the seam for a future server-side ETA normalizer.

The public feeds are not uniform: some provide complete lists, some require a route or station identifier, and some are schedule rather than vehicle-position feeds. Each provider therefore reports availability independently instead of presenting partial data as authoritative.

## Data and privacy

The app uses open Hong Kong government/operator feeds and keeps the last successful snapshot locally in SwiftData. Location is optional, remains on-device, and is only used to sort nearby stops. No API secret is embedded in the client.

The source catalog is maintained in `HongKongTransitCatalog` and should be extended with each new transport dataset's endpoint, attribution, refresh interval, and decoding fixture.
