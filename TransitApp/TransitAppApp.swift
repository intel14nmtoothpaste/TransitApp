import SwiftUI
import SwiftData

@main
struct ConnectingHongKongApp: App {
    @StateObject private var transitStore = TransitStore()
    @StateObject private var locationStore = LocationStore()
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
                .modelContainer(modelContainer)
                .task {
                    transitStore.attach(context: modelContainer.mainContext)
                }
        }
    }
}
