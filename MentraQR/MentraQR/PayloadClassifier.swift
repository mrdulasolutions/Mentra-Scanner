import Foundation

/// Typed decision about a decoded QR payload (Laya-shaped).
struct PayloadDecision: Equatable, Sendable {
    enum Source: String, Sendable {
        case heuristic
        case layaCoreML
        /// Heuristic label with Laya guardrail or full Laya merge.
        case cascade
    }

    let label: String
    let detail: String?
    let confidence: Double?
    let source: Source
    /// When true, UI should warn and block one-tap open until reviewed.
    let reviewRecommended: Bool
    /// Laya `choice` probabilities when available.
    let choiceProbabilities: [String: Double]?
    /// Laya `noul` P(true) for suspicious link / payment risk.
    let suspiciousScore: Double?

    init(
        label: String,
        detail: String?,
        confidence: Double?,
        source: Source,
        reviewRecommended: Bool = false,
        choiceProbabilities: [String: Double]? = nil,
        suspiciousScore: Double? = nil
    ) {
        self.label = label
        self.detail = detail
        self.confidence = confidence
        self.source = source
        self.reviewRecommended = reviewRecommended
        self.choiceProbabilities = choiceProbabilities
        self.suspiciousScore = suspiciousScore
    }
}

/// Classifies decoded scan text after Vision (barcodes + OCR). Laya answers typed questions about fused text.
protocol PayloadClassifying: Sendable {
    func classify(context: ScanClassificationContext) async -> PayloadDecision
}

extension PayloadClassifying {
    func classify(payload: String) async -> PayloadDecision {
        let finding = ScanFinding(
            id: ParcelKey.normalize(payload),
            source: .barcode,
            symbology: nil,
            rawText: payload,
            boundingBox: nil,
            lastSeen: Date(),
            parsed: ShippingBarcodeParser.parse(text: payload, symbology: nil)
        )
        return await classify(context: ScanClassificationContext(finding: finding, relatedOcrExcerpt: nil))
    }
}

/// Fast, on-device rules for common QR and shipping barcode content.
struct HeuristicPayloadClassifier: PayloadClassifying {
    func classify(context: ScanClassificationContext) async -> PayloadDecision {
        let sym = context.finding.symbology?.lowercased() ?? ""
        if sym.contains("qr"), let parsed = context.finding.parsed, parsed.isQRContent || !parsed.isParcelShipment {
            if let kind = parsed.kind {
                let preview = String(context.finding.rawText.prefix(48))
                return PayloadDecision(
                    label: kind,
                    detail: preview.count < context.finding.rawText.count ? preview + "…" : preview,
                    confidence: 0.92,
                    source: .heuristic
                )
            }
        }

        if let parsed = context.finding.parsed {
            if let carrier = parsed.carrier, let tracking = parsed.trackingId {
                return PayloadDecision(
                    label: carrier,
                    detail: tracking,
                    confidence: 0.95,
                    source: .heuristic
                )
            }
            if let carrier = parsed.carrier {
                return PayloadDecision(
                    label: carrier,
                    detail: parsed.kind,
                    confidence: 0.9,
                    source: .heuristic
                )
            }
            if let kind = parsed.kind {
                return PayloadDecision(
                    label: kind,
                    detail: parsed.trackingId,
                    confidence: 0.88,
                    source: .heuristic
                )
            }
        }
        if context.finding.source == .ocr {
            let preview = String(context.finding.rawText.prefix(60))
            return PayloadDecision(
                label: "Label text",
                detail: preview + (context.finding.rawText.count > 60 ? "…" : ""),
                confidence: 0.85,
                source: .heuristic
            )
        }

        let trimmed = context.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PayloadDecision(label: "Empty", detail: nil, confidence: 1, source: .heuristic)
        }

        if trimmed.uppercased().hasPrefix("WIFI:") {
            return PayloadDecision(label: "Wi‑Fi", detail: "Network join QR", confidence: 1, source: .heuristic)
        }
        if trimmed.uppercased().hasPrefix("BEGIN:VCARD") {
            return PayloadDecision(label: "Contact", detail: "vCard", confidence: 1, source: .heuristic)
        }
        if trimmed.uppercased().hasPrefix("BEGIN:VEVENT") || trimmed.uppercased().hasPrefix("BEGIN:VCALENDAR") {
            return PayloadDecision(label: "Calendar", detail: nil, confidence: 1, source: .heuristic)
        }
        if trimmed.lowercased().hasPrefix("mailto:") {
            return PayloadDecision(label: "Email link", detail: nil, confidence: 1, source: .heuristic)
        }
        if trimmed.lowercased().hasPrefix("tel:") || trimmed.lowercased().hasPrefix("sms:") {
            return PayloadDecision(label: "Phone / SMS", detail: nil, confidence: 1, source: .heuristic)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                let host = url.host?.lowercased() ?? ""
                if host.contains("paypal") || host.contains("venmo") || host.contains("cash.app") {
                    return PayloadDecision(label: "Payment URL", detail: host, confidence: 0.9, source: .heuristic)
                }
                return PayloadDecision(label: "Web URL", detail: host.isEmpty ? nil : host, confidence: 0.95, source: .heuristic)
            }
            return PayloadDecision(label: "Link", detail: scheme, confidence: 0.9, source: .heuristic)
        }

        if trimmed.count > 120 {
            return PayloadDecision(label: "Long text", detail: "\(trimmed.count) characters", confidence: 0.8, source: .heuristic)
        }
        return PayloadDecision(label: "Plain text", detail: nil, confidence: 0.7, source: .heuristic)
    }
}

/// Laya question templates (one `predict` call: kind + suspicious). See docs/LAYA_INTEGRATION.md.
enum LayaQRPayloadQuestions {
    static let suspicious = (
        id: "suspicious",
        instructions: "Does this text describe a deceptive or high-risk link or payment request?"
    )

    static let payloadKind = (
        id: "kind",
        instructions: "What kind of content does this text represent?",
        criteria: [
            "web": "http or https URLs and web pages",
            "payment": "money transfer, invoice, or wallet links",
            "contact": "email, phone, or address book entries",
            "other": "everything else",
        ]
    )

    /// Question dict shape for Python `laya.predict` / future Core ML encoder.
    static func questionDictionary() -> [String: Any] {
        [
            suspicious.id: [
                "type": "noul",
                "instructions": suspicious.instructions,
            ],
            payloadKind.id: [
                "type": "choice",
                "instructions": payloadKind.instructions,
                "criteria": payloadKind.criteria,
            ],
        ]
    }
}
