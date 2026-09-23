import SwiftUI

struct WiFiSetupView: View {
    @EnvironmentObject private var session: MentraSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WiFiMatchBanner(
                        match: session.wifiNetworkMatch,
                        phoneSSID: session.phoneWifiSSID,
                        glassesSSID: session.glassesWifiSSID,
                        phoneIP: session.phoneLanIP,
                        glassesIP: session.glassesWifiLocalIP,
                        onRequestLocation: { session.requestPhoneWiFiPermission() }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Glasses Wi-Fi") {
                    TextField("SSID", text: $session.wifiSSID)
                    SecureField("Password", text: $session.wifiPassword)
                    Button("Scan networks on glasses") {
                        session.requestWifiScan()
                    }
                    .disabled(!session.isConnected)

                    if !session.wifiNetworks.isEmpty {
                        ForEach(session.wifiNetworks, id: \.self) { ssid in
                            Button(ssid) {
                                session.wifiSSID = ssid
                            }
                        }
                    }

                    Button("Send credentials to glasses") {
                        session.sendWifiCredentials()
                    }
                    .disabled(!session.isConnected || session.wifiSSID.isEmpty)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Wi‑Fi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        session.refreshPhoneNetwork()
                    }
                }
            }
            .onAppear {
                session.requestPhoneWiFiPermission()
            }
        }
    }
}
