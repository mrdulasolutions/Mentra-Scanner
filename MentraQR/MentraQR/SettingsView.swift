import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: MentraSession

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

                Section {
                    Toggle(isOn: Binding(
                        get: { session.labelOCREnabled },
                        set: { session.setLabelOCREnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Label text (OCR)")
                            Text("Reads printed text on labels. Off by default for QR and barcode scanning only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Scanning")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
