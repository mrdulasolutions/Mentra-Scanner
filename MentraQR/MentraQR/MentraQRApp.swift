import SwiftUI

@main
struct MentraQRApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = MentraSession()
    @StateObject private var captureLibrary = LabelCaptureLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(captureLibrary)
                .tint(AppDesign.accent)
                .onAppear {
                    session.bindCaptureLibrary(captureLibrary)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                session.requestPhoneWiFiPermission()
            }
        }
    }
}
