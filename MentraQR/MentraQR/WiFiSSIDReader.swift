import CoreLocation
import Foundation
import NetworkExtension

/// iOS requires location permission before `NEHotspotNetwork.fetchCurrent` returns the Wi‑Fi SSID.
enum WiFiSSIDAccessResult: Equatable, Sendable {
    case ssid(String)
    case notOnWiFi
    case locationDenied
    case locationRestricted
    case locationNotDetermined
}

@MainActor
final class WiFiSSIDReader: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiSSIDReader()

    private let locationManager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    /// Prompts for When-In-Use location if needed, then reads the current Wi‑Fi SSID.
    func fetchSSIDWithAuthorization() async -> WiFiSSIDAccessResult {
        let status = await ensureWhenInUseAuthorization()
        switch status {
        case .denied:
            return .locationDenied
        case .restricted:
            return .locationRestricted
        case .notDetermined:
            return .locationNotDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return .locationDenied
        }

        let ssid = await PhoneNetworkInfo.fetchCurrentWiFiSSID()
        guard let ssid, !ssid.isEmpty else {
            return .notOnWiFi
        }
        return .ssid(ssid)
    }

    func requestAuthorizationIfNeeded() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    private func ensureWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let current = locationManager.authorizationStatus
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: status)
        }
    }
}
