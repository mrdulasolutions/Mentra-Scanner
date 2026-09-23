import CoreML
import Foundation

/// Tunable after `scripts/laya_payload_eval.py` on real scans.
enum LayaClassificationThresholds {
    /// Compare `suspiciousScore` (noul P(true)) against this to set `reviewRecommended`.
    static let suspiciousNoul: Double = 0.54
    /// Below this top `choice` probability → treat as low confidence (review).
    static let choiceConfidence: Double = 0.72
}

/// Laya-shaped inference: Core ML when a bundled `.mlpackage` is present; otherwise keyword risk heuristics.
final class LayaCoreMLPayloadClassifier: PayloadClassifying, @unchecked Sendable {
    private let lock = NSLock()
    private var model: MLModel?
    private var loadAttempted = false

    private static let bundledModelName = "LayaMultilingualANE"

    func classify(context: ScanClassificationContext) async -> PayloadDecision {
        let payload = context.classificationText
        let state = PayloadURLShaping.forLaya(payload)
        if let model = await loadModelIfNeeded() {
            if let mlDecision = await runCoreML(model: model, state: state, originalPayload: context.primaryText) {
                return mlDecision
            }
        }
        return heuristicLayaStandIn(state: state, originalPayload: context.primaryText)
    }

    private func loadModelIfNeeded() async -> MLModel? {
        lock.lock()
        defer { lock.unlock() }
        if loadAttempted { return model }
        loadAttempted = true
        guard let url = Bundle.main.url(forResource: Self.bundledModelName, withExtension: "mlpackage")
            ?? Bundle.main.url(forResource: Self.bundledModelName, withExtension: "mlmodelc") else {
            return nil
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: url, configuration: config)
        } catch {
            model = nil
        }
        return model
    }

    /// Spike: inspect package I/O in Xcode and port tokenization from laya-coreml before enabling production inference.
    private func runCoreML(model: MLModel, state: String, originalPayload: String) async -> PayloadDecision? {
        // Model I/O varies by export; return nil to use stand-in until tokenizer + feature provider are wired.
        _ = model
        _ = state
        _ = originalPayload
        return nil
    }

    private func heuristicLayaStandIn(state: String, originalPayload: String) -> PayloadDecision {
        let risk = LinkRiskHeuristics.suspiciousScore(for: state, fullPayload: originalPayload)
        let review = risk >= LayaClassificationThresholds.suspiciousNoul

        let kind = kindChoice(for: originalPayload)
        let topProb = kind.probabilities[kind.choice] ?? 0.5
        let lowConfidence = topProb < LayaClassificationThresholds.choiceConfidence

        return PayloadDecision(
            label: kind.displayLabel,
            detail: kind.detail,
            confidence: topProb,
            source: .layaCoreML,
            reviewRecommended: review || lowConfidence,
            choiceProbabilities: kind.probabilities,
            suspiciousScore: risk
        )
    }

    private struct KindChoice {
        let choice: String
        let displayLabel: String
        let detail: String?
        let probabilities: [String: Double]
    }

    private func kindChoice(for payload: String) -> KindChoice {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("wifi:") {
            return KindChoice(choice: "other", displayLabel: "Wi‑Fi", detail: nil, probabilities: ["other": 0.95, "web": 0.02, "payment": 0.01, "contact": 0.02])
        }
        if lower.hasPrefix("begin:vcard") {
            return KindChoice(choice: "contact", displayLabel: "Contact", detail: "vCard", probabilities: ["contact": 0.96, "other": 0.04])
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let host = url.host?.lowercased() ?? ""
            if host.contains("paypal") || host.contains("venmo") || host.contains("cash.app") {
                return KindChoice(choice: "payment", displayLabel: "Payment URL", detail: host, probabilities: ["payment": 0.88, "web": 0.1, "other": 0.02])
            }
            return KindChoice(choice: "web", displayLabel: "Web URL", detail: host.isEmpty ? nil : host, probabilities: ["web": 0.9, "payment": 0.05, "other": 0.05])
        }
        if lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") || lower.hasPrefix("sms:") {
            return KindChoice(choice: "contact", displayLabel: "Contact link", detail: nil, probabilities: ["contact": 0.92, "other": 0.08])
        }
        return KindChoice(choice: "other", displayLabel: "Plain text", detail: nil, probabilities: ["other": 0.75, "web": 0.15, "contact": 0.1])
    }
}

enum LinkRiskHeuristics {
    private static let riskyHostFragments = [
        "login", "signin", "verify", "secure", "account", "wallet", "crypto", "bit.ly", "tinyurl",
        "t.co", "goo.gl", "rb.gy", "is.gd",
    ]
    private static let riskyPathFragments = [
        "password", "credential", "otp", "2fa", "urgent", "invoice", "refund",
    ]

    /// Returns P(true) for a deceptive / high-risk link (Laya `noul` stand-in).
    static func suspiciousScore(for shapedState: String, fullPayload: String) -> Double {
        let blob = (shapedState + " " + fullPayload).lowercased()
        var score = 0.0
        for frag in riskyHostFragments where blob.contains(frag) {
            score += 0.22
        }
        for frag in riskyPathFragments where blob.contains(frag) {
            score += 0.15
        }
        if fullPayload.lowercased().hasPrefix("http://") && !fullPayload.lowercased().hasPrefix("http://localhost") {
            score += 0.12
        }
        if blob.contains("@") && blob.contains("http") {
            score += 0.25
        }
        return min(1.0, score)
    }
}
