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
                Text("—")
                    .font(Theme.Font.noteDisplay)
                    .foregroundStyle(Theme.Color.secondaryText)
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
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
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

// MARK: - Banner

private struct Banner: View {
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
    TunerView(detector: MockPitchDetector())
        .frame(width: 720, height: 480)
}
