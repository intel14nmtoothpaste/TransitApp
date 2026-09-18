@preconcurrency import CoreLocation
import Combine
import Foundation

/// Wraps Core Location so the map and nearby-stop ranking can react to permission changes.
@MainActor
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            requestAccess()
            return
        }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }
}
