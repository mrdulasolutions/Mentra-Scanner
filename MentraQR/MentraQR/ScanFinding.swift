import CoreGraphics
import Foundation

enum ScanSource: String, Sendable, Equatable {
    case barcode
    case ocr
}

/// Live WHIP frames vs one-shot hi-res label capture.
enum ScanCaptureContext: String, Sendable, Equatable {
    case live
    case labelSnapshot
}

struct ParsedShipment: Equatable, Sendable {
    let carrier: String?
    let trackingId: String?
    let kind: String?

    var parcelKey: String? {
        if !isParcelShipment { return nil }
        if let trackingId, !trackingId.isEmpty {
            return ParcelKey.normalize(trackingId)
        }
        return nil
    }

    /// Carrier tracking / shipping label — not generic QR, URL, or product barcodes.
    var isParcelShipment: Bool {
        if carrier != nil { return true }
        let k = kind?.lowercased() ?? ""
        if k.contains("tracking") { return true }
        if k.contains("carrier") { return true }
        return false
    }

    var isQRContent: Bool {
        let k = kind?.lowercased() ?? ""
        if k.contains("qr") { return true }
        if k == "url" { return true }
        if k.contains("wi-fi") { return true }
        return false
    }
}

enum ParcelKey {
    static func normalize(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    static func barcodeTrackingKey(symbology: String, raw: String) -> String {
        "bc:\(symbology.lowercased()):\(normalize(raw))"
    }

    static func ocrExcerptKey(_ excerpt: String) -> String {
        "ocr:\(normalize(excerpt).prefix(80))"
    }

    static func ocrLineKey(_ line: String) -> String {
        "ocr-line:\(normalize(line).prefix(64))"
    }

    static func snapshotQRKey(_ payload: String) -> String {
        "snap-qr:\(normalize(payload).prefix(80))"
    }

    static func snapshotOcrLineKey(_ line: String) -> String {
        "snap-ocr-line:\(normalize(line).prefix(64))"
    }

    static func snapshotOcrBlockKey(_ excerpt: String) -> String {
        "snap-ocr:\(normalize(excerpt).prefix(80))"
    }
}

struct ScanFinding: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let source: ScanSource
    /// Vision symbology name or "label_text" for OCR.
    let symbology: String?
    let rawText: String
    let boundingBox: CGRect?
    let lastSeen: Date
    let parsed: ParsedShipment?
    var captureContext: ScanCaptureContext = .live

    var normalizedKey: String { id }

    /// Backward-compatible alias for QR-era code paths.
    var payload: String { rawText }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Classification input fused for heuristics / Laya.
struct ScanClassificationContext: Sendable {
    let finding: ScanFinding
    let relatedOcrExcerpt: String?

    var primaryText: String { finding.rawText }

    var classificationText: String {
        var parts: [String] = []
        if let sym = finding.symbology, finding.source == .barcode {
            parts.append("symbology: \(sym)")
        }
        parts.append("text: \(PayloadURLShaping.forLaya(finding.rawText))")
        if let carrier = finding.parsed?.carrier {
            parts.append("carrier: \(carrier)")
        }
        if let tracking = finding.parsed?.trackingId {
            parts.append("tracking: \(tracking)")
        }
        if let ocr = relatedOcrExcerpt, !ocr.isEmpty {
            parts.append("label: \(PayloadURLShaping.forLaya(String(ocr.prefix(300))))")
        }
        return parts.joined(separator: " | ")
    }
}
