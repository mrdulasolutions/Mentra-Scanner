import SwiftUI

struct ScanResultRow: View {
    let finding: ScanFinding
    var decision: PayloadDecision?

    private var payload: String { finding.rawText }

    private var httpURL: URL? {
        guard let url = URL(string: payload),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(finding.displaySymbology)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                if finding.captureContext == .labelSnapshot {
                    Text("Hi-res capture")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let detail = finding.fieldPresentation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let decision {
                HStack(spacing: 6) {
                    Text(decision.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(chipColor(for: decision).opacity(0.2))
                        .clipShape(Capsule())
                    if decision.reviewRecommended {
                        Text("Review")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    if let detail = decision.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(sourceCaption(decision.source))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(payload)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .lineLimit(finding.fieldPresentation.kind == .labelExcerpt ? 12 : 6)
            HStack {
                Button("Copy") {
                    UIPasteboard.general.string = payload
                }
                if let url = httpURL {
                    if decision?.reviewRecommended == true {
                        Text("Open blocked — review first")
                            .foregroundStyle(.secondary)
                    } else {
                        Link("Open", destination: url)
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func chipColor(for decision: PayloadDecision) -> Color {
        decision.reviewRecommended ? .orange : .accentColor
    }

    private func sourceCaption(_ source: PayloadDecision.Source) -> String {
        switch source {
        case .heuristic: "rules"
        case .layaCoreML: "laya"
        case .cascade: "cascade"
        }
    }
}
