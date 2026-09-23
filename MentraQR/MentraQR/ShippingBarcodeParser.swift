import Foundation

enum ShippingBarcodeParser {
    /// Parse carrier / tracking / product from barcode or OCR text.
    static func parse(text: String, symbology: String?) -> ParsedShipment? {
        let normalized = BarcodePayloadNormalizer.normalize(text)
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let upper = text.uppercased()
        let sym = symbology?.lowercased() ?? ""
        let digits = normalizedDigits(trimmed)

        if let ups = parseUPS(from: trimmed, upper: upper) {
            return ups
        }
        if let fedex = parseFedEx(upper: upper, digits: digits, symbology: sym) {
            return fedex
        }
        if let usps = parseUSPS(upper: upper, digits: digits) {
            return usps
        }
        if isLikelyProductBarcode(sym: sym, text: trimmed, digits: digits) {
            return ParsedShipment(carrier: nil, trackingId: nil, kind: "Product barcode")
        }
        if sym.contains("qr") {
            return parseQRCodePayload(trimmed)
        }
        if trimmed.lowercased().hasPrefix("http") {
            return nil
        }
        if digits.count >= 10 {
            return ParsedShipment(carrier: nil, trackingId: trimmed, kind: "Barcode (\(digits.count) digits)")
        }
        return ParsedShipment(carrier: nil, trackingId: trimmed, kind: "Barcode")
    }

    static func mergeParsed(_ a: ParsedShipment?, _ b: ParsedShipment?) -> ParsedShipment? {
        guard a != nil || b != nil else { return nil }
        let carrier = a?.carrier ?? b?.carrier
        let tracking = a?.trackingId ?? b?.trackingId
        let kind = a?.kind ?? b?.kind
        if carrier == nil, tracking == nil, kind == nil { return nil }
        return ParsedShipment(carrier: carrier, trackingId: tracking, kind: kind)
    }

    static func normalizedDigits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    /// Non-carrier QR payloads (URL, Wi‑Fi join, plain text).
    static func parseQRCodePayload(_ text: String) -> ParsedShipment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return ParsedShipment(carrier: nil, trackingId: nil, kind: "URL")
        }
        if lower.hasPrefix("wifi:") {
            return ParsedShipment(carrier: nil, trackingId: nil, kind: "Wi‑Fi QR")
        }
        if lower.hasPrefix("mailto:") {
            return ParsedShipment(carrier: nil, trackingId: nil, kind: "Email QR")
        }
        if lower.hasPrefix("tel:") {
            return ParsedShipment(carrier: nil, trackingId: nil, kind: "Phone QR")
        }
        if let carrier = parseFedEx(upper: trimmed.uppercased(), digits: normalizedDigits(trimmed), symbology: "qr") {
            return carrier
        }
        if let ups = parseUPS(from: BarcodePayloadNormalizer.normalize(trimmed), upper: trimmed.uppercased()) {
            return ups
        }
        if let usps = parseUSPS(upper: trimmed.uppercased(), digits: normalizedDigits(trimmed)) {
            return usps
        }
        return ParsedShipment(carrier: nil, trackingId: nil, kind: "QR code")
    }

    private static func parseUPS(from normalized: String, upper: String) -> ParsedShipment? {
        let alnum = normalized.uppercased().filter { $0.isLetter || $0.isNumber }
        let pattern = #"1Z[0-9A-Z]{16}"#
        if let match = alnum.range(of: pattern, options: .regularExpression) {
            let tracking = String(alnum[match])
            return ParsedShipment(carrier: "UPS", trackingId: tracking, kind: "Tracking")
        }
        if let match = upper.range(of: pattern, options: .regularExpression) {
            let tracking = String(upper[match]).replacingOccurrences(of: " ", with: "")
            return ParsedShipment(carrier: "UPS", trackingId: tracking, kind: "Tracking")
        }
        return nil
    }

    private static func parseFedEx(upper: String, digits: String, symbology: String) -> ParsedShipment? {
        if let trk = parseFedExTRKLine(upper) {
            return ParsedShipment(carrier: "FedEx", trackingId: trk, kind: "Tracking")
        }

        let fedexKeyword = upper.contains("FEDEX")
            || upper.contains("FDXG")
            || upper.contains("FDEG")
            || upper.contains("FDE")
            || upper.contains("FXSP")
            || upper.contains("FED EX")
            || upper.contains("TRK#")
            || upper.contains("TRACKING #")

        if let tracking = fedExTrackingFromDigitsOnly(digits, symbology: symbology) {
            return ParsedShipment(carrier: "FedEx", trackingId: tracking, kind: "Tracking")
        }

        if fedexKeyword {
            if let tracking = pickFedExTrackingDigits(digits) {
                return ParsedShipment(carrier: "FedEx", trackingId: tracking, kind: "Tracking")
            }
            return ParsedShipment(carrier: "FedEx", trackingId: nil, kind: "Carrier label")
        }
        return nil
    }

    /// FedEx Ground/Home linear barcode: 34 digits starting with 96; last 12 = TRK#.
    private static func fedExTrackingFromDigitsOnly(_ digits: String, symbology: String) -> String? {
        let sym = symbology.lowercased()
        let isLinear = sym.contains("code128") || sym.contains("pdf417") || sym.contains("code39")

        if digits.count == 34, digits.hasPrefix("96") {
            return String(digits.suffix(12))
        }
        if digits.count == 32, digits.hasPrefix("96") {
            return String(digits.suffix(12))
        }
        if digits.count == 22, digits.hasPrefix("96"), isLinear {
            return String(digits.suffix(12))
        }
        if digits.count == 12, isLinear || digits.hasPrefix("96") {
            return digits
        }
        if digits.count == 15, isLinear {
            return digits
        }
        if digits.count == 20, isLinear {
            return digits
        }
        return nil
    }

    private static func parseFedExTRKLine(_ upper: String) -> String? {
        let pattern = #"TRK#?\s*([0-9]{4}\s+[0-9]{4}\s+[0-9]{4,6})"#
        guard let match = upper.range(of: pattern, options: .regularExpression) else { return nil }
        let slice = String(upper[match])
        let digits = normalizedDigits(slice)
        if digits.count >= 12 {
            return String(digits.prefix(12))
        }
        return digits.isEmpty ? nil : digits
    }

    private static func pickFedExTrackingDigits(_ digits: String) -> String? {
        if let fed = fedExTrackingFromDigitsOnly(digits, symbology: "ocr") {
            return fed
        }
        if digits.count >= 12 {
            return String(digits.suffix(12))
        }
        return nil
    }

    private static func parseUSPS(upper: String, digits: String) -> ParsedShipment? {
        if let tracking = uspsTrackingDigits(digits) {
            return ParsedShipment(carrier: "USPS", trackingId: tracking, kind: "Tracking")
        }
        if upper.contains("USPS") || upper.contains("PRIORITY MAIL") {
            return ParsedShipment(carrier: "USPS", trackingId: nil, kind: "Carrier label")
        }
        return nil
    }

    private static func uspsTrackingDigits(_ digits: String) -> String? {
        let patterns = ["9405", "9400", "9205", "9215", "9303", "9270"]
        for prefix in patterns {
            if let range = digits.range(of: prefix) {
                let tail = String(digits[range.lowerBound...])
                if tail.count >= 20 {
                    return String(tail.prefix(22))
                }
            }
        }
        if digits.count >= 20, digits.hasPrefix("94") {
            return String(digits.prefix(22))
        }
        return nil
    }

    private static func isLikelyProductBarcode(sym: String, text: String, digits: String) -> Bool {
        guard digits.count >= 8, digits.count <= 14 else { return false }
        let productSyms = ["ean13", "ean8", "upce", "itf14"]
        if productSyms.contains(where: { sym.contains($0) }) {
            return true
        }
        if sym.contains("code128"), digits.count >= 20 {
            return false
        }
        return text == digits && !sym.contains("code128") && !sym.contains("pdf417")
    }

    static func parseOCRText(_ text: String) -> ParsedShipment? {
        let upper = text.uppercased()
        let digits = normalizedDigits(text)
        if let ups = parseUPS(from: BarcodePayloadNormalizer.normalize(text), upper: upper) { return ups }
        if let fedex = parseFedEx(upper: upper, digits: digits, symbology: "ocr") { return fedex }
        if let usps = parseUSPS(upper: upper, digits: digits) { return usps }
        if upper.contains("AMAZON") {
            return ParsedShipment(carrier: "Amazon", trackingId: nil, kind: "Carrier label")
        }
        if upper.contains("DHL") {
            return ParsedShipment(carrier: "DHL", trackingId: nil, kind: "Carrier label")
        }
        if upper.contains("FEDEX") || upper.contains("FED EX") || upper.contains("TRK#") {
            return ParsedShipment(carrier: "FedEx", trackingId: pickFedExTrackingDigits(digits), kind: "Carrier label")
        }
        if upper.contains("USPS") || upper.contains("USPS TRACKING") {
            return ParsedShipment(carrier: "USPS", trackingId: uspsTrackingDigits(digits), kind: "Carrier label")
        }
        return nil
    }

    /// Prefer UPS 1Z / USPS 94xx / FedEx 34-digit over routing-only Code128 (e.g. 42078731…).
    static func rankingScore(for finding: ScanFinding) -> Int {
        let digits = normalizedDigits(finding.rawText)
        if finding.parsed?.carrier == "UPS", finding.parsed?.trackingId?.hasPrefix("1Z") == true { return 100 }
        if finding.parsed?.carrier == "USPS", (finding.parsed?.trackingId?.count ?? 0) >= 20 { return 95 }
        if finding.parsed?.carrier == "FedEx", (finding.parsed?.trackingId?.count ?? 0) >= 12 { return 90 }
        if digits.hasPrefix("420"), digits.count <= 15 { return 10 }
        if finding.parsed?.trackingId != nil { return 50 }
        return 20
    }
}
