import Foundation
import os

enum AppDiagnostics {
    private static let logger = Logger(subsystem: "com.local.mentraqr", category: "app")

    static func log(_ message: String, onAppend: ((String) -> Void)? = nil) {
        let line = "[\(Self.timestamp())] \(message)"
        logger.info("\(message, privacy: .public)")
        onAppend?(line)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
