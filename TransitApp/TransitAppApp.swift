import SwiftUI

@main
struct ConnectingHongKongApp: App {
        // Initialize environment objects

    private let transitService = TransitService()
    private let userPreferences = UserPreferences()
    private let locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transitService)
                .environmentObject(userPreferences)
                .environmentObject(locationManager)
        }
    }
}
