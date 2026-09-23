import Foundation
import MentraBluetoothSDK

/// Mentra Live RGB LED timing (see MentraOS `session.led.solid` / `turnOn`).
enum GlassesFillLight {
    /// One solid-on window per command; app refreshes before this elapses.
    static let solidOnDurationMs = 120_000
    static let keepaliveIntervalSeconds: UInt64 = 40
    static let authoritySettleNanoseconds: UInt64 = 450_000_000
    static let betweenCommandsNanoseconds: UInt64 = 180_000_000

    static func onRequest(requestId: String) -> RgbLedRequest {
        RgbLedRequest(
            requestId: requestId,
            packageName: Bundle.main.bundleIdentifier,
            action: .on,
            color: .white,
            onDurationMs: solidOnDurationMs,
            offDurationMs: 0,
            count: 1
        )
    }

    static func offRequest(requestId: String) -> RgbLedRequest {
        RgbLedRequest(
            requestId: requestId,
            packageName: Bundle.main.bundleIdentifier,
            action: .off,
            color: nil,
            onDurationMs: 0,
            offDurationMs: 0,
            count: 0
        )
    }
}
