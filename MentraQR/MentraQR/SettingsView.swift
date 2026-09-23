import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        WiFiSetupView()
                    } label: {
                        Label("Wi‑Fi", systemImage: "wifi")
                    }

                    NavigationLink {
                        AdvancedFeaturesView()
                    } label: {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
