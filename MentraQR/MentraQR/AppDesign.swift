import SwiftUI

/// Shared spacing, surfaces, and components aligned with Apple HIG (grouped layout + materials).
enum AppDesign {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let accent = Color(red: 0.10, green: 0.40, blue: 0.95)

    static var groupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }
}

struct MentraCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppDesign.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

extension View {
    func mentraCard() -> some View {
        modifier(MentraCardModifier())
    }
}

struct MentraSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MentraStatusPill: View {
    enum Style {
        case neutral, success, warning, active
    }

    let text: String
    var style: Style = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background.opacity(0.18), in: Capsule())
        .foregroundStyle(foreground)
    }

    private var background: Color {
        switch style {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .active: AppDesign.accent
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .active: AppDesign.accent
        }
    }
}

struct MentraEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppDesign.accent)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

struct MentraConnectionStrip: View {
    let isConnected: Bool
    let isLive: Bool
    let glassesWifiSummary: String
    var actionHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isConnected ? "eyeglasses" : "eyeglasses.slash")
                    .font(.title3)
                    .foregroundStyle(isConnected ? AppDesign.accent : .secondary)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnected ? "Mentra Live" : "Not connected")
                        .font(.headline)
                    Text(glassesWifiSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if isLive {
                    MentraStatusPill(text: "Live", style: .success, systemImage: "dot.radiowaves.left.and.right")
                } else if isConnected {
                    MentraStatusPill(text: "Linked", style: .active, systemImage: "link")
                }
            }
            if let actionHint {
                Label(actionHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .mentraCard()
    }
}
