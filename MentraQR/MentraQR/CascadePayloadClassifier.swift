import Foundation

/// Heuristics first; Laya (Core ML or stand-in) for ambiguity and HTTPS guardrails.
struct CascadePayloadClassifier: PayloadClassifying {
    private let heuristics = HeuristicPayloadClassifier()
    private let laya = LayaCoreMLPayloadClassifier()

    func classify(context: ScanClassificationContext) async -> PayloadDecision {
        let base = await heuristics.classify(context: context)
        let text = context.primaryText

        if context.finding.parsed?.carrier != nil, (base.confidence ?? 0) >= 0.88 {
            return base
        }

        if base.isStructuredHighConfidence, !base.needsHTTPSGuardrailCheck(payload: text) {
            return base
        }

        if base.isStructuredHighConfidence, base.needsHTTPSGuardrailCheck(payload: text) {
            let risk = await laya.classify(context: context)
            return base.mergingGuardrail(from: risk)
        }

        let layaDecision = await laya.classify(context: context)
        return base.mergingFullLaya(from: layaDecision)
    }
}

extension PayloadDecision {
    /// Structured QR formats where heuristics alone are sufficient (no Laya kind question).
    var isStructuredHighConfidence: Bool {
        guard source == .heuristic, confidence == 1 else { return false }
        switch label {
        case "Wi‑Fi", "Contact", "Calendar", "Email link", "Phone / SMS":
            return true
        default:
            return false
        }
    }

    func needsHTTPSGuardrailCheck(payload: String) -> Bool {
        let lower = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    func mergingGuardrail(from risk: PayloadDecision) -> PayloadDecision {
        PayloadDecision(
            label: label,
            detail: detail,
            confidence: confidence,
            source: .cascade,
            reviewRecommended: risk.reviewRecommended,
            choiceProbabilities: choiceProbabilities,
            suspiciousScore: risk.suspiciousScore
        )
    }

    func mergingFullLaya(from laya: PayloadDecision) -> PayloadDecision {
        let useHeuristicLabel = isStructuredHighConfidence
        return PayloadDecision(
            label: useHeuristicLabel ? label : laya.label,
            detail: useHeuristicLabel ? detail : laya.detail,
            confidence: useHeuristicLabel ? confidence : laya.confidence,
            source: .cascade,
            reviewRecommended: laya.reviewRecommended,
            choiceProbabilities: laya.choiceProbabilities,
            suspiciousScore: laya.suspiciousScore
        )
    }
}
