import SwiftUI

/// Centralized colors, fonts, and metrics. Reach for these instead of literals.
///
/// Design language — "Night Stage":
/// the app is an instrument under stage lights. The backdrop is deep indigo
/// night with two faint aurora glows (violet overhead, mint low on the
/// horizon — the nacre bands translated into environment). Content floats on
/// translucent lifts with hairline borders (`Stage.swift`). Mother-of-pearl
/// (`Pearlescent`) is the jewel finish, reserved for hero glyphs, inlays,
/// and selected states. One luminous accent — aurora mint — marks the
/// interactive path; semantic tuning colors (green → red) stay untouched so
/// pitch feedback never competes with the accent.
///
/// The window forces dark appearance (`FretworkApp`); the theme is fixed by
/// design. Changing the look remains a one-file edit.
enum Theme {

    // MARK: - Colors

    enum Color {
        /// Stage gradient — the page backdrop, top to bottom.
        static let stageTop       = SwiftUI.Color(red: 0.115, green: 0.110, blue: 0.270)
        static let stageMid       = SwiftUI.Color(red: 0.082, green: 0.078, blue: 0.205)
        static let stageBottom    = SwiftUI.Color(red: 0.048, green: 0.045, blue: 0.125)

        /// Legacy names kept stable; they map onto the stage family.
        static let backgroundTop    = stageTop
        static let backgroundBottom = stageBottom
        static let background       = stageMid

        /// Cards float above the stage as translucent lifts; `surfaceRaised`
        /// is one shelf higher (active chips, popover rows).
        static let surface       = SwiftUI.Color.white.opacity(0.055)
        static let surfaceRaised = SwiftUI.Color.white.opacity(0.10)
        /// 1 px borders that separate a lift from the stage.
        static let hairline      = SwiftUI.Color.white.opacity(0.08)

        static let primaryText   = SwiftUI.Color(red: 0.96, green: 0.95, blue: 0.90)
        static let secondaryText = SwiftUI.Color(red: 0.96, green: 0.95, blue: 0.90).opacity(0.58)
        /// Whisper tier — micro-labels, unit suffixes, ghost numerals.
        static let tertiaryText  = SwiftUI.Color(red: 0.96, green: 0.95, blue: 0.90).opacity(0.36)

        /// Aurora mint — the interactive accent. Luminous on indigo, and a
        /// hue the semantic tuning colors never use, so feedback stays
        /// unambiguous next to controls.
        static let accent     = SwiftUI.Color(red: 0.62, green: 0.92, blue: 0.80)
        /// Pressed / deep variant for fills that need to sit quieter.
        static let accentDeep = SwiftUI.Color(red: 0.42, green: 0.76, blue: 0.62)
        /// Standard tinted-fill strength for accent-backed chips.
        static let accentSoft = accent.opacity(0.16)
        /// Text/glyph color for content printed *on* accent fills.
        static let onAccent   = SwiftUI.Color(red: 0.07, green: 0.09, blue: 0.16)

        /// Tuner / pitch feedback — semantic, kept vivid on the dark stage.
        static let inTune       = SwiftUI.Color(red: 0.30, green: 0.88, blue: 0.48)
        static let nearInTune   = SwiftUI.Color(red: 1.00, green: 0.85, blue: 0.35)
        static let outOfTune    = SwiftUI.Color(red: 1.00, green: 0.64, blue: 0.26)
        static let farOutOfTune = SwiftUI.Color(red: 1.00, green: 0.38, blue: 0.36)

        /// Neutral fill for gauge and meter tracks.
        static let track  = SwiftUI.Color.white.opacity(0.13)
        /// Zero/center markers on gauges.
        static let marker = SwiftUI.Color.white.opacity(0.42)

        /// Instrument-hardware detail (fret wire highlights, octave marks).
        static let brass = SwiftUI.Color(red: 0.90, green: 0.77, blue: 0.54)

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

        // MARK: Fretboard neck material

        /// The "ebony" of the on-screen neck — the sidebar's indigo family,
        /// deepened so note dots and pearl inlays carry the contrast.
        static let neckTop    = SwiftUI.Color(red: 0.155, green: 0.145, blue: 0.360)
        static let neckBottom = SwiftUI.Color(red: 0.085, green: 0.080, blue: 0.225)
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

        /// Note letter at the center of the tuner's halo gauge.
        static let haloNote = SwiftUI.Font.system(size: 92, weight: .bold, design: .rounded)
        /// Oversized octave suffix next to `haloNote`.
        static let haloOctave = SwiftUI.Font.system(size: 30, weight: .semibold, design: .rounded)

        /// Hero numerals (BPM readouts, results percentage).
        static let heroNumber = SwiftUI.Font.system(size: 52, weight: .bold, design: .rounded)
        /// Big-but-not-hero numerals (practice targets, stats).
        static let statNumber = SwiftUI.Font.system(size: 34, weight: .bold, design: .rounded)

        /// The "pro audio gear" label: tiny, wide-tracked, uppercase.
        /// Apply `.tracking(1.6)` and uppercase text at the call site, or
        /// use the `MicroLabel` view in Stage.swift.
        static let microLabel = SwiftUI.Font.system(size: 10, weight: .semibold, design: .rounded)
    }

    // MARK: - Layout

    enum Metrics {
        /// Legacy radius — retained for callers that predate the tiered set.
        static let cornerRadius: CGFloat = 12
        /// Page-level cards and panels.
        static let radiusCard: CGFloat = 14
        /// Chips, pills, and elements nested inside cards.
        static let radiusInner: CGFloat = 10

        static let cardPadding: CGFloat  = 24
        static let sectionSpacing: CGFloat = 16
        /// Outer margin between page content and the window edge.
        static let pagePadding: CGFloat = 20
        /// Spacing around control bars (pickers, toolbars) at the top of a page.
        static let controlSpacing: CGFloat = 12
    }
}
