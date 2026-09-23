import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var session: MentraSession
    @State private var statusExpanded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(session.isConnected ? AppDesign.accent.opacity(0.15) : Color.secondary.opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: session.isConnected ? "eyeglasses" : "eyeglasses.slash")
                                .font(.title2)
                                .foregroundStyle(session.isConnected ? AppDesign.accent : .secondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.isConnected ? "Connected" : "Not connected")
                                .font(.title3.weight(.semibold))
                            Text(statusSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    DisclosureGroup(isExpanded: $statusExpanded) {
                        LabeledContent("Connection", value: session.connectionStatus)
                        LabeledContent("Battery", value: session.batteryText)
                        LabeledContent("Wi‑Fi match", value: session.wifiNetworkMatch.title)
                        LabeledContent("iPhone Wi‑Fi", value: session.phoneWifiSSID ?? "Unavailable")
                        LabeledContent("Phone LAN", value: session.phoneLanIP)
                        LabeledContent("Glasses Wi‑Fi", value: session.glassesWifiSSID ?? "Not connected")
                    } label: {
                        Label("Technical details", systemImage: "gauge.with.dots.needle.67percent")
                    }
                }

                Section("Nearby glasses") {
                    if session.discoveredDevices.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(session.isScanningBLE ? "Scanning for Mentra Live…" : "No devices found")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            Spacer()
                        }
                    } else {
                        ForEach(session.discoveredDevices, id: \.id) { device in
                            Button {
                                session.selectedDevice = device
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.body.weight(.medium))
                                        Text(device.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if session.selectedDevice?.id == device.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppDesign.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        session.startBLEScan()
                    } label: {
                        Label("Scan for Mentra Live", systemImage: "dot.radiowaves.left.and.right")
                    }

                    Button {
                        session.connectSelected()
                    } label: {
                        Label("Connect to selected", systemImage: "link")
                    }
                    .disabled(session.discoveredDevices.isEmpty && session.selectedDevice == nil)

                    Button {
                        session.connectDefault()
                    } label: {
                        Label("Reconnect saved glasses", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        session.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(!session.isConnected)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.requestPhoneWiFiPermission()
                        session.refreshPhoneNetwork()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh network status")
                }
            }
        }
    }

    private var statusSummary: String {
        if session.isConnected {
            return session.batteryText
        }
        return "Pair Mentra Live to start scanning labels and QR codes."
    }
}
