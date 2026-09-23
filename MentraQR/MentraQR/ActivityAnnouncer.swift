import AudioToolbox
import Foundation
import UIKit

/// Haptics and subtle system sounds only — no speech (warehouse / high-volume friendly).
@MainActor
final class ActivityAnnouncer {
    func playCameraShutter() {
        AudioServicesPlaySystemSound(1108)
    }

    func playCountdownTick() {
        AudioServicesPlaySystemSound(1057)
    }

    func announceConnection(connected: Bool, deviceName: String?) {
        guard connected else { return }
        impact(.light)
    }

    func announceLiveScan(started: Bool) {}

    func announceManualScanCapturing() {
        playCameraShutter()
    }

    func announceManualScanResult(findingsCount: Int) {
        notifyLabelCaptured(fieldCount: findingsCount)
    }

    func announceManualScanFailed(_ message: String) {
        notification(.error)
    }

    func announceLabelCaptureSaved(triggerReason: String, findingsCount: Int) {}

    func announceCodeDetected(summary: String) {}

    func announceStreamStatus(_ status: String) {
        let lower = status.lowercased()
        if lower.contains("failed") || lower.contains("error") {
            notification(.error)
        }
    }

    func announceFillLight(on: Bool) {}

    func notifyLabelCaptured(fieldCount: Int) {
        impact(fieldCount > 0 ? .medium : .light)
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
