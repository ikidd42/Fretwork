import SwiftUI

/// Centralized colors, fonts, and metrics. Reach for these instead of literals.
///
/// The app runs a fixed dark-indigo brand theme (the window forces dark
/// appearance in `FretworkApp`): indigo gradient surfaces, cream text, and
/// mother-of-pearl accents (`Pearlescent`). Feedback colors stay vivid
/// against the dark board. Changing the look remains a one-file edit.
enum Theme {

    // MARK: - Colors

    enum Color {
        /// Detail-pane gradient — the sidebar's indigo family, deeper, so
        /// the fretboard sidebar still reads as its own surface.
        static let backgroundTop    = SwiftUI.Color(red: 0.135, green: 0.125, blue: 0.31)
        static let backgroundBottom = SwiftUI.Color(red: 0.075, green: 0.07, blue: 0.185)
        /// Flat fallback where a single color is needed.
        static let background       = SwiftUI.Color(red: 0.10, green: 0.095, blue: 0.245)
        /// Cards float above the gradient as translucent lifts.
        static let surface          = SwiftUI.Color.white.opacity(0.07)
        static let primaryText     = SwiftUI.Color(red: 0.96, green: 0.95, blue: 0.90)
        static let secondaryText   = SwiftUI.Color(red: 0.96, green: 0.95, blue: 0.90).opacity(0.58)
        static let accent           = SwiftUI.Color.accentColor

        /// Tuner / pitch feedback.
        static let inTune           = SwiftUI.Color.green
        static let nearInTune       = SwiftUI.Color.yellow
        static let outOfTune        = SwiftUI.Color.orange
        static let farOutOfTune     = SwiftUI.Color.red

        /// Neutral fill for gauge and meter tracks.
        static let track            = SwiftUI.Color.white.opacity(0.13)
        /// Zero/center markers on gauges.
        static let marker           = SwiftUI.Color.white.opacity(0.42)

        /// Returns a tuning-feedback color for an absolute cents-off value.
        static func tuningColor(centsOff: Double) -> SwiftUI.Color {
            let absCents = Swift.abs(centsOff)
            if absCents < 5  { return inTune }
            if absCents < 15 { return nearInTune }
            if absCents < 30 { return outOfTune }
            return farOutOfTune
        }

        // MARK: Sidebar (fretboard identity — matches the app icon)

        /// The sidebar stays dark indigo in both appearances; it's the
        /// brand surface, not a semantic one.
        static let sidebarTop      = SwiftUI.Color(red: 0.24, green: 0.22, blue: 0.50)
        static let sidebarBottom   = SwiftUI.Color(red: 0.11, green: 0.10, blue: 0.30)
        /// The "strings" and "frets" drawn over the sidebar.
        static let sidebarString   = SwiftUI.Color(red: 0.93, green: 0.92, blue: 0.88)
        /// Warm cream used for the selected item — the icon's inlay dot.
        static let inlay           = SwiftUI.Color(red: 0.98, green: 0.97, blue: 0.90)
        /// Sidebar label colors (fixed, since the surface is fixed).
        static let sidebarText         = SwiftUI.Color.white.opacity(0.78)
        static let sidebarTextSelected = SwiftUI.Color(red: 0.99, green: 0.98, blue: 0.93)
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
        /// Outer margin between page content and the window edge.
        static let pagePadding: CGFloat = 20
        /// Spacing around control bars (pickers, toolbars) at the top of a page.
        static let controlSpacing: CGFloat = 12
    }
}
