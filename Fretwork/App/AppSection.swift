import SwiftUI

/// Top-level navigation destinations shown in the sidebar.
///
/// Adding a new feature mode is one case here plus a `case` in `RootView`'s switch.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case tuner
    case flashCards
    case fretboard
    case practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tuner:        "Tuner"
        case .flashCards:   "Flash Cards"
        case .fretboard:    "Fretboard"
        case .practice:     "Practice"
        }
    }

    var symbolName: String {
        switch self {
        case .tuner:        "tuningfork"
        case .flashCards:   "rectangle.on.rectangle"
        case .fretboard:    "guitars"
        case .practice:     "metronome"
        }
    }
}
