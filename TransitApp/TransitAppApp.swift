import SwiftUI
import SwiftData

/// Application entry point for the Hong Kong Transit experience.
@main
struct ConnectingHongKongApp: App {
    @StateObject private var transitStore = TransitStore()
    @StateObject private var locationStore = LocationStore()
    @StateObject private var favoritesStore = FavoritesStore()
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: CachedTransitSnapshot.self)
        } catch {
            fatalError("Unable to configure local transit cache: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TransitAppRootView()
                .environmentObject(transitStore)
                .environmentObject(locationStore)
                .environmentObject(favoritesStore)
                .modelContainer(modelContainer)
                .task {
                    transitStore.attach(context: modelContainer.mainContext)
                }
        }
    }
}
