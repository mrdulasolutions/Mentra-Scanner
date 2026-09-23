import SwiftUI

/// SDK / developer capabilities kept out of the default photo-first workflow.
struct AdvancedFeaturesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Scan uses continuous live streaming and saves frames from the video feed. Optional developer tools are below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Developer") {
                    NavigationLink {
                        LegacyStreamingView()
                    } label: {
                        Label("WHIP live stream controls", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                Section("Coming soon") {
                    Label("Custom photo pipelines", systemImage: "camera.aperture")
                    Label("Alternate transfer methods", systemImage: "arrow.triangle.swap")
                    Label("Raw frame export", systemImage: "film")
                }
                .foregroundStyle(.secondary)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
