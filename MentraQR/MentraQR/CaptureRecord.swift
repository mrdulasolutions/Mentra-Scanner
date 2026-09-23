import CoreGraphics
import Foundation

/// Vision-normalized label ROI stored with a capture.
struct StoredLabelROI: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct StoredScanFinding: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(source):\(symbology ?? ""):\(rawText)" }
    let source: String
    let symbology: String?
    let rawText: String
    let captureContext: String
    let carrier: String?
    let trackingId: String?
    let kind: String?

    init(from finding: ScanFinding) {
        source = finding.source.rawValue
        symbology = finding.symbology
        rawText = finding.rawText
        captureContext = finding.captureContext.rawValue
        carrier = finding.parsed?.carrier
        trackingId = finding.parsed?.trackingId
        kind = finding.parsed?.kind
    }
}

struct LabelCaptureRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let triggerReason: String
    let frameWidth: Int
    let frameHeight: Int
    /// Filename only, relative to the captures images directory.
    let imageFileName: String
    let findings: [StoredScanFinding]
    let labelROI: StoredLabelROI?

    var imageFileURL: URL {
        LabelCapturePaths.imagesDirectory.appendingPathComponent(imageFileName)
    }

    var summaryLine: String {
        if findings.isEmpty {
            return "No parsed fields"
        }
        let presentations = findings.map(\.fieldPresentation)
        if let ship = presentations.first(where: { $0.section == .shipping }) {
            if let tracking = findings.compactMap(\.trackingId).first {
                return "\(ship.title) · \(tracking)"
            }
            return ship.title
        }
        if let qr = presentations.first(where: { $0.section == .qrAndLinks }) {
            return "\(qr.title) · \(excerpt(findings.first?.rawText ?? "", limit: 28))"
        }
        if let first = presentations.first {
            return "\(first.title) · \(findings.count) field\(findings.count == 1 ? "" : "s")"
        }
        return "\(findings.count) fields"
    }

    private func excerpt(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }
}

enum LabelCapturePaths {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MentraQR", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var imagesDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("CaptureImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("captures.sqlite")
    }
}
