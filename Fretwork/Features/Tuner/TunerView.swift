import SwiftUI

/// First vertical slice: read the mic, identify the played note, show how far off it is.
struct TunerView: View {
    @State private var viewModel: TunerViewModel

    init(detector: any PitchDetector) {
        _viewModel = State(wrappedValue: TunerViewModel(detector: detector))
    }

    var body: some View {
        VStack(spacing: 32) {
            permissionBanner

            noteDisplay

            CentsIndicator(
                centsOff: viewModel.smoothedCentsOff,
                isActive: viewModel.smoothedNote != nil
            )
            .frame(height: 56)
            .padding(.horizontal, 40)

            Text(viewModel.frequencyDisplay)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.secondaryText)
                .monospacedDigit()

            Spacer()
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Subviews

    private var noteDisplay: some View {
        ZStack {
            if let note = viewModel.smoothedNote {
                Text(note.pitchClass.sharpName)
                    .font(Theme.Font.noteDisplay)
                    .foregroundStyle(Theme.Color.tuningColor(centsOff: viewModel.smoothedCentsOff))
                    .overlay(alignment: .topTrailing) {
                        Text("\(note.octave)")
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .offset(x: 24, y: 24)
                    }
            } else {
                // Idle: the biggest glyph in the app gets the full pearl
                // treatment while it waits. Once a note lands, functional
                // tuning color takes over.
                Text("—")
                    .font(Theme.Font.noteDisplay)
                    .pearlShimmer()
            }
        }
        .frame(height: 180)
        .animation(.snappy(duration: 0.15), value: viewModel.smoothedNote)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        switch viewModel.permission {
        case .denied:
            Banner(
                text: "Microphone access denied. Enable Fretwork in System Settings → Privacy & Security → Microphone.",
                tint: Theme.Color.farOutOfTune
            )
        case .undetermined, .granted:
            if let error = viewModel.lastError {
                Banner(text: error, tint: Theme.Color.outOfTune)
            }
        }
    }
}

// MARK: - Cents indicator

private struct CentsIndicator: View {
    let centsOff: Double
    let isActive: Bool

    /// Display range in cents on either side of zero.
    private let range: Double = 50

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let clamped = max(-range, min(range, centsOff))
                let xOffset = (clamped / range) * (width / 2)

                ZStack {
                    Capsule()
                        .fill(Theme.Color.track)
                        .frame(height: 8)

                    Rectangle()
                        .fill(Theme.Color.marker)
                        .frame(width: 2, height: 28)

                    if isActive {
                        Circle()
                            .fill(Theme.Color.tuningColor(centsOff: centsOff))
                            .frame(width: 22, height: 22)
                            .offset(x: xOffset)
                            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: centsOff)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 32)

            HStack {
                Text("−50¢")
                Spacer()
                Text("0")
                Spacer()
                Text("+50¢")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.secondaryText)
        }
    }
}

#Preview {
    TunerView(detector: MockPitchDetector())
        .frame(width: 720, height: 480)
}
