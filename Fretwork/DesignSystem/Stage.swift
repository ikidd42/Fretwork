import SwiftUI

/// The stage every page plays on, plus the small cast of shared components
/// that keep the "Night Stage" language consistent: translucent lift cards,
/// wide-tracked micro-labels, and tinted pills.
///
/// Reach for `StageBackdrop` behind each detail page, `.stageCard()` for
/// content panels, `MicroLabel` for section/tag labels, and `PillBadge`
/// for compact status readouts.

// MARK: - Backdrop

/// Deep indigo night with two faint aurora glows — violet overhead, mint on
/// the lower trailing horizon (the nacre bands translated into environment)
/// — and a soft vignette so the edges fall off like an unlit stage.
struct StageBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.Color.stageTop, Theme.Color.stageMid, Theme.Color.stageBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color(red: 0.45, green: 0.40, blue: 0.95).opacity(0.14), .clear],
                center: .init(x: 0.5, y: -0.12),
                startRadius: 0,
                endRadius: 620
            )
        )
        .overlay(
            RadialGradient(
                colors: [Theme.Color.accent.opacity(0.05), .clear],
                center: .init(x: 1.05, y: 1.05),
                startRadius: 0,
                endRadius: 520
            )
        )
        .overlay(
            // Vignette: edges sink so the lit center reads as a stage.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.22)],
                center: .center,
                startRadius: 320,
                endRadius: 900
            )
        )
        .ignoresSafeArea()
    }
}

// MARK: - Card

/// Standard content panel: a translucent lift with a faint top-down sheen,
/// a 1 px hairline, and a soft shadow to separate it from the stage.
private struct StageCard: ViewModifier {
    var padding: CGFloat = Theme.Metrics.cardPadding
    var radius: CGFloat = Theme.Metrics.radiusCard

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.075), Color.white.opacity(0.045)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Color.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

extension View {
    /// Present this view as a Night Stage content panel. See `StageCard`.
    func stageCard(
        padding: CGFloat = Theme.Metrics.cardPadding,
        radius: CGFloat = Theme.Metrics.radiusCard
    ) -> some View {
        modifier(StageCard(padding: padding, radius: radius))
    }
}

// MARK: - Micro label

/// The "pro audio gear" label — tiny, uppercase, wide-tracked, whisper tier.
/// Used for panel headers, field labels, and unit tags.
struct MicroLabel: View {
    let text: String
    var color: Color = Theme.Color.tertiaryText

    init(_ text: String, color: Color = Theme.Color.tertiaryText) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.microLabel)
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

// MARK: - Section header

/// Card/panel header row: a micro-label on the leading edge, optional
/// trailing content (counts, toggles, pills).
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            MicroLabel(title)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: - Pill badge

/// Compact tinted capsule for status readouts — score counts, live
/// indicators, detected-chord chips.
struct PillBadge: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.Color.accent
    /// When true the text renders in the tint color; otherwise primary.
    var tintedText: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(Theme.Font.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tintedText ? tint : Theme.Color.primaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        StageBackdrop()
        VStack(spacing: 16) {
            SectionHeader("Signal Chain") {
                PillBadge(text: "LIVE", symbol: "circle.fill", tint: Theme.Color.inTune)
            }
            Text("Content")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.primaryText)
        }
        .stageCard()
        .padding(40)
    }
    .frame(width: 520, height: 320)
}
