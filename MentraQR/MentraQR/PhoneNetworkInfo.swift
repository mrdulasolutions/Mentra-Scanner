import Foundation
import NetworkExtension

enum WiFiNetworkMatch: Equatable {
    case unknown
    case phoneUnavailable
    case phoneLocationDenied
    case glassesNotOnWifi
    case match
    case mismatch(phone: String, glasses: String)

    var title: String {
        switch self {
        case .unknown:
            return "Checking networks…"
        case .phoneUnavailable:
            return "Phone Wi‑Fi name unavailable"
        case .phoneLocationDenied:
            return "Location needed for Wi‑Fi name"
        case .glassesNotOnWifi:
            return "Glasses not on Wi‑Fi"
        case .match:
            return "Networks match"
        case .mismatch:
            return "Networks do not match"
        }
    }

    var isMatch: Bool {
        if case .match = self { return true }
        return false
    }
}

enum PhoneNetworkInfo {
    static func fetchCurrentWiFiSSID() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                let ssid = network?.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ssid?.isEmpty == false ? ssid : nil)
            }
        }
    }

    static func compareNetworks(
        phoneSSID: String?,
        glassesSSID: String?,
        glassesConnected: Bool,
        phoneAccess: WiFiSSIDAccessResult?
    ) -> WiFiNetworkMatch {
        guard glassesConnected, let glassesSSID, !glassesSSID.isEmpty else {
            return .glassesNotOnWifi
        }
        if phoneAccess == .locationDenied || phoneAccess == .locationRestricted {
            return .phoneLocationDenied
        }
        guard let phoneSSID, !phoneSSID.isEmpty else {
            return .phoneUnavailable
        }
        if normalize(phoneSSID) == normalize(glassesSSID) {
            return .match
        }
        return .mismatch(phone: phoneSSID, glasses: glassesSSID)
    }

    private static func normalize(_ ssid: String) -> String {
        ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
