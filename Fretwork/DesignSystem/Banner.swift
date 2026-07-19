import SwiftUI

/// Inline notice strip for errors and permission prompts.
///
/// Tint conveys severity (`Theme.Color.outOfTune` for recoverable problems,
/// `Theme.Color.farOutOfTune` for blockers); the leading icon makes the
/// severity legible at a glance, and the tinted lift + hairline keeps it
/// readable on the stage without shouting.
struct Banner: View {
    let text: String
    let tint: Color
    var symbol: String = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.16), tint.opacity(0.09)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        StageBackdrop()
        VStack {
            Banner(text: "Microphone access denied.", tint: Theme.Color.farOutOfTune)
            Banner(text: "Could not switch input device.", tint: Theme.Color.outOfTune, symbol: "bolt.trianglebadge.exclamationmark.fill")
        }
        .padding()
        .frame(width: 420)
    }
}
