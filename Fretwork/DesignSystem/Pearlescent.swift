import SwiftUI

/// Mother-of-pearl finish for the sidebar's text and inlays.
///
/// Real nacre reads as soft pastel bands — blush, mint, ice blue, lavender
/// over a cream base — with a sheen that drifts as the viewing angle
/// changes. Two layers approximate that:
///
/// 1. A static pastel gradient across the glyphs (the iridescent banding).
/// 2. A slow diagonal highlight sweeping through, masked to the content
///    (the moving sheen). One ~9 s cycle, driven by a phase the sidebar
///    owns so every inlay shimmers under the same "light", with a small
///    per-element offset so the sweep arrives down the board in sequence.
///
/// Deliberately restrained: low-saturation stops and a faint highlight —
/// jewelry, not a loading indicator.
struct Pearlescent: ViewModifier, Animatable {
    /// Animation phase in [0, 1), supplied by the container.
    var phase: Double
    /// Per-element cycle offset so pieces don't flash in unison.
    var offset: Double = 0
    /// Dims the whole finish for de-emphasized (unselected) elements.
    var intensity: Double = 1

    /// Without this, SwiftUI snaps `phase` to its final value instead of
    /// interpolating — the sheen would freeze on the first frame.
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    /// Nacre band palette, cream-anchored. Saturated a touch beyond real
    /// nacre — at sidebar text sizes, subtler stops read as plain white.
    private static let bands: [Color] = [
        Color(red: 0.98, green: 0.95, blue: 0.84),  // cream
        Color(red: 0.97, green: 0.80, blue: 0.85),  // blush
        Color(red: 0.76, green: 0.94, blue: 0.86),  // mint
        Color(red: 0.76, green: 0.87, blue: 0.98),  // ice blue
        Color(red: 0.88, green: 0.81, blue: 0.98),  // lavender
        Color(red: 0.98, green: 0.95, blue: 0.84),  // cream again
    ]

    /// The banded gradient shared by the animated and static variants.
    static func bandGradient(intensity: Double) -> LinearGradient {
        LinearGradient(
            colors: bands.map { $0.opacity(intensity) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func body(content: Content) -> some View {
        let local = (phase + offset).truncatingRemainder(dividingBy: 1)

        content
            .foregroundStyle(Self.bandGradient(intensity: intensity))
            .overlay(
                // The sheen: a narrow diagonal highlight travelling across.
                GeometryReader { geo in
                    let travel = geo.size.width + geo.size.height
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.85 * intensity), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: max(geo.size.width * 0.45, 20))
                    .offset(x: -geo.size.width * 0.8 + travel * local * 1.6)
                }
                .mask(content)
            )
    }
}

extension View {
    /// Apply the mother-of-pearl finish. See `Pearlescent`.
    func pearlescent(phase: Double, offset: Double = 0, intensity: Double = 1) -> some View {
        modifier(Pearlescent(phase: phase, offset: offset, intensity: intensity))
    }

    /// The static pearl finish: iridescent banding without the animated
    /// sheen. Costs nothing per frame, so it's safe to use on every
    /// heading in the app — reserve the animated `pearlescent(phase:)`
    /// for hero elements.
    func pearlStatic(intensity: Double = 1) -> some View {
        foregroundStyle(Pearlescent.bandGradient(intensity: intensity))
    }

    /// Animated pearl that drives its own phase — for standalone hero
    /// text (card prompts, big titles) outside the sidebar's shared cycle.
    func pearlShimmer() -> some View {
        modifier(PearlShimmer())
    }
}

/// Self-driving wrapper around `Pearlescent` for isolated hero elements.
struct PearlShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    func body(content: Content) -> some View {
        content
            .pearlescent(phase: phase)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
