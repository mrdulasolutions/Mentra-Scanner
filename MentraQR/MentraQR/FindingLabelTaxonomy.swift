import Foundation

// MARK: - Inventory (sources we normalize)
//
// Internal symbology tokens: label_line, label_text
// Vision barcodes: QR, Code128, PDF417, EAN-13, …
// ParsedShipment.kind: Tracking, Carrier label, QR code, URL, Wi‑Fi QR, Product barcode, Barcode, …
// ParsedShipment.carrier: UPS, FedEx, USPS, Amazon, DHL
// PayloadDecision.label: Web URL, Label text, …

/// User-facing section for grouped lists.
enum ScanFieldSection: String, CaseIterable, Sendable {
    case shipping = "Shipping & tracking"
    case qrAndLinks = "QR & links"
    case barcodes = "Barcodes"
    case labelText = "Label text"
    case other = "Other"
}

/// Stable field type for chips and voice prompts.
enum ScanFieldKind: String, Sendable {
    case trackingNumber
    case carrierMention
    case qrCode
    case url
    case wifiJoin
    case emailLink
    case phoneLink
    case shippingBarcode
    case productBarcode
    case genericBarcode
    case labelLine
    case labelExcerpt
    case plainText
    case unknown
}

struct ScanFieldPresentation: Sendable, Equatable {
    let section: ScanFieldSection
    let kind: ScanFieldKind
    /// Primary chip (e.g. "FedEx tracking", "Label line").
    let title: String
    /// Optional detail chip (carrier name, symbology short name).
    let detail: String?
}

enum FindingLabelTaxonomy {
    static func present(_ finding: ScanFinding) -> ScanFieldPresentation {
        present(
            source: finding.source.rawValue,
            symbology: finding.symbology,
            rawText: finding.rawText,
            carrier: finding.parsed?.carrier,
            trackingId: finding.parsed?.trackingId,
            parsedKind: finding.parsed?.kind,
            isHiRes: finding.captureContext == .labelSnapshot
        )
    }

    static func present(_ stored: StoredScanFinding) -> ScanFieldPresentation {
        present(
            source: stored.source,
            symbology: stored.symbology,
            rawText: stored.rawText,
            carrier: stored.carrier,
            trackingId: stored.trackingId,
            parsedKind: stored.kind,
            isHiRes: stored.captureContext == ScanCaptureContext.labelSnapshot.rawValue
        )
    }

    static func groupedStoredFindings(_ findings: [StoredScanFinding]) -> [(section: ScanFieldSection, items: [StoredScanFinding])] {
        let order = ScanFieldSection.allCases
        var buckets: [ScanFieldSection: [StoredScanFinding]] = [:]
        for finding in findings {
            let section = present(finding).section
            buckets[section, default: []].append(finding)
        }
        return order.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    static func groupedFindings(_ findings: [ScanFinding]) -> [(section: ScanFieldSection, items: [ScanFinding])] {
        let order = ScanFieldSection.allCases
        var buckets: [ScanFieldSection: [ScanFinding]] = [:]
        for finding in findings {
            let section = present(finding).section
            buckets[section, default: []].append(finding)
        }
        return order.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    // MARK: - Core mapping

    private static func present(
        source: String,
        symbology: String?,
        rawText: String,
        carrier: String?,
        trackingId: String?,
        parsedKind: String?,
        isHiRes: Bool
    ) -> ScanFieldPresentation {
        let sym = symbology?.lowercased() ?? ""
        let kindLower = parsedKind?.lowercased() ?? ""

        if source == ScanSource.ocr.rawValue {
            return presentOCR(symbology: sym, isHiRes: isHiRes, carrier: carrier, trackingId: trackingId, parsedKind: kindLower)
        }

        if sym.contains("qr") {
            return presentQR(parsedKind: kindLower, carrier: carrier, trackingId: trackingId, isHiRes: isHiRes)
        }

        if let carrier, let trackingId, !trackingId.isEmpty {
            return ScanFieldPresentation(
                section: .shipping,
                kind: .trackingNumber,
                title: "\(carrier) tracking",
                detail: shortBarcodeSymbology(symbology)
            )
        }

        if let carrier, trackingId == nil || trackingId?.isEmpty == true {
            if kindLower.contains("carrier") {
                return ScanFieldPresentation(
                    section: .shipping,
                    kind: .carrierMention,
                    title: "\(carrier) label",
                    detail: shortBarcodeSymbology(symbology)
                )
            }
        }

        if kindLower.contains("tracking"), let carrier {
            return ScanFieldPresentation(
                section: .shipping,
                kind: .trackingNumber,
                title: "\(carrier) tracking",
                detail: shortBarcodeSymbology(symbology)
            )
        }

        if kindLower.contains("product") {
            return ScanFieldPresentation(
                section: .barcodes,
                kind: .productBarcode,
                title: "Product barcode",
                detail: shortBarcodeSymbology(symbology)
            )
        }

        if kindLower.contains("barcode") {
            return ScanFieldPresentation(
                section: .barcodes,
                kind: .genericBarcode,
                title: "Barcode",
                detail: shortBarcodeSymbology(symbology) ?? parsedKind
            )
        }

        if source == ScanSource.barcode.rawValue {
            return ScanFieldPresentation(
                section: .barcodes,
                kind: .shippingBarcode,
                title: "Shipping barcode",
                detail: shortBarcodeSymbology(symbology)
            )
        }

        return ScanFieldPresentation(
            section: .other,
            kind: .unknown,
            title: "Unclassified",
            detail: symbology
        )
    }

    private static func presentOCR(
        symbology: String,
        isHiRes: Bool,
        carrier: String?,
        trackingId: String?,
        parsedKind: String
    ) -> ScanFieldPresentation {
        if let carrier, let trackingId, !trackingId.isEmpty {
            return ScanFieldPresentation(
                section: .shipping,
                kind: .trackingNumber,
                title: "\(carrier) tracking (OCR)",
                detail: nil
            )
        }
        if let carrier {
            return ScanFieldPresentation(
                section: .shipping,
                kind: .carrierMention,
                title: "\(carrier) label (OCR)",
                detail: nil
            )
        }

        let hi = isHiRes ? " (hi-res)" : ""
        if symbology == "label_line" {
            return ScanFieldPresentation(
                section: .labelText,
                kind: .labelLine,
                title: "Label line\(hi)",
                detail: nil
            )
        }
        if symbology == "label_text" {
            return ScanFieldPresentation(
                section: .labelText,
                kind: .labelExcerpt,
                title: "Label excerpt\(hi)",
                detail: nil
            )
        }

        return ScanFieldPresentation(
            section: .labelText,
            kind: .plainText,
            title: "Printed text\(hi)",
            detail: nil
        )
    }

    private static func presentQR(
        parsedKind: String,
        carrier: String?,
        trackingId: String?,
        isHiRes: Bool
    ) -> ScanFieldPresentation {
        let hi = isHiRes ? " (hi-res)" : ""

        if let carrier, let trackingId, !trackingId.isEmpty {
            return ScanFieldPresentation(
                section: .shipping,
                kind: .trackingNumber,
                title: "\(carrier) tracking (QR)",
                detail: nil
            )
        }

        if parsedKind.contains("wi-fi") || parsedKind.contains("wifi") {
            return ScanFieldPresentation(section: .qrAndLinks, kind: .wifiJoin, title: "Wi‑Fi QR\(hi)", detail: nil)
        }
        if parsedKind == "url" || parsedKind.contains("url") {
            return ScanFieldPresentation(section: .qrAndLinks, kind: .url, title: "URL\(hi)", detail: nil)
        }
        if parsedKind.contains("email") {
            return ScanFieldPresentation(section: .qrAndLinks, kind: .emailLink, title: "Email QR\(hi)", detail: nil)
        }
        if parsedKind.contains("phone") {
            return ScanFieldPresentation(section: .qrAndLinks, kind: .phoneLink, title: "Phone QR\(hi)", detail: nil)
        }

        return ScanFieldPresentation(
            section: .qrAndLinks,
            kind: .qrCode,
            title: "QR code\(hi)",
            detail: carrier
        )
    }

    static func shortBarcodeSymbology(_ symbology: String?) -> String? {
        guard let symbology, !symbology.isEmpty else { return nil }
        let lower = symbology.lowercased()
        if lower.contains("code128") { return "Code 128" }
        if lower.contains("pdf417") { return "PDF417" }
        if lower.contains("qrcode") || lower == "qr" { return "QR" }
        if lower.contains("ean13") { return "EAN-13" }
        if lower.contains("ean8") { return "EAN-8" }
        if lower.contains("upce") { return "UPC-E" }
        if lower.contains("code39") { return "Code 39" }
        if lower.contains("code93") { return "Code 93" }
        if lower.contains("itf14") { return "ITF-14" }
        if lower.contains("datamatrix") { return "Data Matrix" }
        if lower.contains("aztec") { return "Aztec" }
        if lower.contains("gs1") { return "GS1 DataBar" }
        if lower == "label_line" { return nil }
        if lower == "label_text" { return nil }
        return symbology
            .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .replacingOccurrences(of: "Barcode", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ScanFinding {
    var fieldPresentation: ScanFieldPresentation {
        FindingLabelTaxonomy.present(self)
    }

    var displaySymbology: String {
        fieldPresentation.title
    }
}

extension StoredScanFinding {
    var fieldPresentation: ScanFieldPresentation {
        FindingLabelTaxonomy.present(self)
    }
}
