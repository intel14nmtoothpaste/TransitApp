import CoreLocation
import MapKit
import SwiftUI

struct TransitAppRootView: View {
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var location: LocationStore
    @State private var selection: AppSection? = .map

    enum AppSection: Hashable {
        case map
        case routes
        case alerts
        case settings
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Nearby", systemImage: "map")
                    .tag(AppSection.map)
                Label("Routes", systemImage: "arrow.triangle.swap")
                    .tag(AppSection.routes)
                Label("Service alerts", systemImage: "exclamationmark.triangle")
                    .tag(AppSection.alerts)
                Label("Settings", systemImage: "gearshape")
                    .tag(AppSection.settings)
            }
            .navigationTitle("Hong Kong Transit")
        } detail: {
            Group {
                switch selection ?? .map {
                case .map: NearbyView()
                case .routes: RoutesView()
                case .alerts: AlertsView()
                case .settings: SettingsView()
                }
            }
        }
        .task {
            location.start()
            store.startLiveUpdates()
            await store.refresh(force: true)
        }
        .onDisappear { store.stopLiveUpdates() }
    }
}

struct NearbyView: View {
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var location: LocationStore
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var nearbyStops: [TransitStop] {
        guard let coordinate = location.coordinate else { return Array(store.snapshot.stops.prefix(50)) }
        return store.nearbyStops(around: coordinate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $position) {
                    ForEach(nearbyStops) { stop in
                        Annotation(stop.name, coordinate: stop.location) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .accessibilityLabel(stop.name)
                        }
                    }
                }
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                HStack {
                    VStack(alignment: .leading) {
                        Text("Live network")
                            .font(.title2.bold())
                        Text(store.snapshot.fetchedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isRefreshing { ProgressView() }
                    Button { Task { await store.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Refresh transit data")
                }

                if let error = store.lastError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !store.snapshot.arrivals.isEmpty {
                    Text("Next arrivals").font(.title2.bold())
                    ForEach(store.snapshot.arrivals.prefix(8)) { arrival in
                        ArrivalRow(arrival: arrival)
                    }
                }

                Text("Nearby stops").font(.title2.bold())
                ForEach(nearbyStops.prefix(12)) { stop in
                    Label {
                        VStack(alignment: .leading) {
                            Text(stop.name)
                            Text(stop.provider).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Nearby")
    }
}

struct ArrivalRow: View {
    let arrival: Arrival

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: arrival.mode.systemImage)
                .frame(width: 30)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("\(arrival.routeNumber) · \(arrival.destination)").font(.headline)
                Text(arrival.provider).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let minutes = arrival.minutesAway {
                Text(minutes == 0 ? "Due" : "\(minutes) min")
                    .font(.headline)
                    .monospacedDigit()
            } else {
                Text(arrival.status ?? "Scheduled")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct RoutesView: View {
    @EnvironmentObject private var store: TransitStore
    @State private var query = ""

    var routes: [TransitRoute] {
        guard !query.isEmpty else { return store.snapshot.routes }
        return store.snapshot.routes.filter {
            "\($0.number) \($0.origin) \($0.destination)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(routes) { route in
            VStack(alignment: .leading, spacing: 6) {
                Text("\(route.number) · \(route.operatorName)").font(.headline)
                Text("\(route.origin) → \(route.destination)")
                Label(route.mode.rawValue.capitalized, systemImage: route.mode.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .searchable(text: $query, prompt: "Search route or destination")
        .navigationTitle("Routes")
        .overlay {
            if routes.isEmpty {
                ContentUnavailableView("No routes yet", systemImage: "arrow.triangle.swap", description: Text("Refresh live feeds or try another search."))
            }
        }
    }
}

struct AlertsView: View {
    @EnvironmentObject private var store: TransitStore

    var body: some View {
        List(store.snapshot.alerts) { alert in
            VStack(alignment: .leading, spacing: 6) {
                Label(alert.title, systemImage: alert.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(alert.message)
                Text(alert.publishedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Service alerts")
        .overlay {
            if store.snapshot.alerts.isEmpty {
                ContentUnavailableView("No active alerts", systemImage: "checkmark.circle", description: Text("The app will show operator disruptions here when feeds provide them."))
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var location: LocationStore

    var body: some View {
        Form {
            Section("Location") {
                Button("Enable nearby stops") { location.requestAccess() }
                Text(location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways ? "Location access is enabled." : "Location is optional and stays on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Data sources") {
                Text("Open feeds are queried directly when appropriate. A future aggregation service can be injected for high-frequency ETA normalization without changing this UI.")
                    .font(.footnote)
                Link("Hong Kong open data catalog", destination: URL(string: "https://data.gov.hk/tc-datasets/category/transport")!)
            }
        }
        .navigationTitle("Settings")
    }
}
