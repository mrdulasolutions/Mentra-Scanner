import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ConnectView()
                .tabItem {
                    Label("Connect", systemImage: "eyeglasses")
                }

            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }

            CapturesView()
                .tabItem {
                    Label("Captures", systemImage: "tray.full.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(AppDesign.accent)
    }
}
