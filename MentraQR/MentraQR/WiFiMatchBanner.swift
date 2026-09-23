import SwiftUI
import UIKit

struct WiFiMatchBanner: View {
    let match: WiFiNetworkMatch
    let phoneSSID: String?
    let glassesSSID: String?
    let phoneIP: String
    let glassesIP: String?
    var onRequestLocation: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(match.title)
                    .font(.subheadline.bold())
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("iPhone Wi‑Fi")
                        .foregroundStyle(.secondary)
                    Text(phoneSSID ?? "Unavailable")
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("iPhone LAN IP")
                        .foregroundStyle(.secondary)
                    Text(phoneIP)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Glasses Wi‑Fi")
                        .foregroundStyle(.secondary)
                    Text(glassesSSID ?? "Not connected")
                        .textSelection(.enabled)
                }
                if let glassesIP, !glassesIP.isEmpty {
                    GridRow {
                        Text("Glasses LAN IP")
                            .foregroundStyle(.secondary)
                        Text(glassesIP)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.caption)

            if case let .mismatch(phone, glasses) = match {
                Text("Phone is on “\(phone)” but glasses are on “\(glasses)”. Connect the glasses to the same network as this iPhone for streaming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if match == .phoneLocationDenied {
                Text("Apple requires Location permission to read the Wi‑Fi network name. Enable “While Using the App” for Mentra Scanner in Settings, or tap below to allow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let onRequestLocation {
                        Button("Allow location", action: onRequestLocation)
                            .font(.caption)
                    }
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .font(.caption)
                    }
                }
            } else if match == .phoneUnavailable {
                Text("iOS did not report the Wi‑Fi name. Join Wi‑Fi, disable VPN, allow Location if prompted, and tap Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if match == .match {
                Text("SSID matches. If video still fails, the router may block device-to-device traffic (AP isolation).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(backgroundColor.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(backgroundColor.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var iconName: String {
        switch match {
        case .match:
            return "checkmark.circle.fill"
        case .mismatch:
            return "xmark.circle.fill"
        case .glassesNotOnWifi, .phoneUnavailable, .phoneLocationDenied:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch match {
        case .match:
            return .green
        case .mismatch:
            return .red
        case .glassesNotOnWifi, .phoneUnavailable, .phoneLocationDenied:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        iconColor
    }
}
