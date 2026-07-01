import SwiftUI

/// Centralized colors, fonts, and metrics. Reach for these instead of literals.
///
/// Everything is built on system semantic colors so light/dark mode "just works"
/// and a future user-configurable theme is a one-file change.
enum Theme {

    // MARK: - Colors

    enum Color {
        static let background       = SwiftUI.Color(NSColor.windowBackgroundColor)
        static let surface          = SwiftUI.Color(NSColor.controlBackgroundColor)
        static let primaryText      = SwiftUI.Color.primary
        static let secondaryText    = SwiftUI.Color.secondary
        static let accent           = SwiftUI.Color.accentColor

        /// Tuner / pitch feedback.
        static let inTune           = SwiftUI.Color.green
        static let nearInTune       = SwiftUI.Color.yellow
        static let outOfTune        = SwiftUI.Color.orange
        static let farOutOfTune     = SwiftUI.Color.red

        /// Returns a tuning-feedback color for an absolute cents-off value.
        static func tuningColor(centsOff: Double) -> SwiftUI.Color {
            let absCents = Swift.abs(centsOff)
            if absCents < 5  { return inTune }
            if absCents < 15 { return nearInTune }
            if absCents < 30 { return outOfTune }
            return farOutOfTune
        }
    }

    // MARK: - Typography

    enum Font {
        static let title    = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.semibold)
        static let heading  = SwiftUI.Font.system(.title2, design: .rounded).weight(.medium)
        static let body     = SwiftUI.Font.system(.body, design: .rounded)
        static let caption  = SwiftUI.Font.system(.caption, design: .rounded)
        static let mono     = SwiftUI.Font.system(.body, design: .monospaced)

        /// Massive note display used by the tuner ("A4").
        static let noteDisplay = SwiftUI.Font.system(size: 144, weight: .bold, design: .rounded)
    }

    // MARK: - Layout

    enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let cardPadding: CGFloat  = 24
        static let sectionSpacing: CGFloat = 16
    }
}
