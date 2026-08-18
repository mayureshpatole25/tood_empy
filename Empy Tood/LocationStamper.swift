import CoreLocation

/// A one-shot "where am I, roughly" lookup for the journal's optional
/// location stamp. Never blocks writing or saving — if permission isn't
/// granted, or anything fails, the completion just receives `nil` and the
/// entry saves without a stamp.
@MainActor
final class LocationStamper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationStamper()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var completion: ((String?) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
    }

    func requestLabel(completion: @escaping (String?) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // resumes in locationManagerDidChangeAuthorization
        default:
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.finish(nil)
            case .notDetermined:
                break // still waiting on the system prompt
            default:
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return finishOnMain(nil) }
        Task { @MainActor in
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                let label = placemarks?.first.flatMap(Self.label(for:))
                self?.finish(label)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishOnMain(nil)
    }

    private nonisolated func finishOnMain(_ label: String?) {
        Task { @MainActor in self.finish(label) }
    }

    private func finish(_ label: String?) {
        completion?(label)
        completion = nil
    }

    private static func label(for placemark: CLPlacemark) -> String? {
        let neighborhood = placemark.subLocality
        let city = placemark.locality
        let parts = [neighborhood, city].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        return placemark.administrativeArea
    }
}
