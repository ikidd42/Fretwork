import SwiftUI

/// Inline notice strip for errors and permission prompts.
///
/// Tint conveys severity (`Theme.Color.outOfTune` for recoverable problems,
/// `Theme.Color.farOutOfTune` for blockers); the text stays primary for
/// readability on the translucent fill.
struct Banner: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }
}

#Preview {
    VStack {
        Banner(text: "Microphone access denied.", tint: Theme.Color.farOutOfTune)
        Banner(text: "Could not switch input device.", tint: Theme.Color.outOfTune)
    }
    .padding()
    .frame(width: 400)
}
