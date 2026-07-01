import SwiftUI

/// Interactive fretboard: pick a key and scale, see every in-scale note on the
/// neck with its degree label, and watch the note you're playing light up.
struct FretboardView: View {
    @State private var viewModel: FretboardViewModel

    init(detector: any PitchDetector, chordDetector: (any ChordDetector)? = nil) {
        _viewModel = State(wrappedValue: FretboardViewModel(
            detector: detector,
            chordDetector: chordDetector
        ))
    }

    @State private var showCircleOfFifths = true

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, Theme.Metrics.cardPadding)
                .padding(.top, Theme.Metrics.sectionSpacing)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: Theme.Metrics.sectionSpacing) {
                // Fretboard + scale info (takes priority width)
                VStack(spacing: 0) {
                    FretboardCanvas(viewModel: viewModel)
                        .padding(.bottom, Theme.Metrics.sectionSpacing)

                    scaleInfoBar
                }
                .frame(maxWidth: .infinity)

                // Circle of fifths companion (collapsible)
                if showCircleOfFifths {
                    CircleOfFifthsView(
                        selectedRoot: $viewModel.selectedRoot,
                        accidental: viewModel.accidental,
                        activePitchClass: viewModel.activePitchClass,
                        scalePitchClasses: viewModel.scalePitchClasses
                    )
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
            .padding(.bottom, Theme.Metrics.sectionSpacing)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            // Root picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Key")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Picker("Key", selection: $viewModel.selectedRoot) {
                    ForEach(PitchClass.allCases, id: \.self) { pc in
                        Text(pc.name(preferring: viewModel.accidental))
                            .tag(pc)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }

            // Scale picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Scale")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Picker("Scale", selection: $viewModel.selectedScale) {
                    ForEach(Scale.catalog) { scale in
                        Text(scale.name).tag(scale)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            // Tuning picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Tuning")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Picker("Tuning", selection: $viewModel.selectedTuning) {
                    ForEach(Tuning.catalog) { tuning in
                        Text(tuning.name).tag(tuning)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            // Accidental toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Accidentals")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
                Picker("Accidentals", selection: $viewModel.accidental) {
                    Text("♯").tag(Accidental.sharp)
                    Text("♭").tag(Accidental.flat)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }

            Spacer()

            // Chord detection toggle
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.showChordDetection.toggle()
                }
            } label: {
                Label("Chords",
                      systemImage: viewModel.showChordDetection
                      ? "pianokeys.inverse" : "pianokeys")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.showChordDetection ? Theme.Color.accent : Theme.Color.secondaryText)
            .help("Toggle chord detection")

            // Circle of fifths toggle
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    showCircleOfFifths.toggle()
                }
            } label: {
                Label("Circle of 5ths",
                      systemImage: showCircleOfFifths ? "circle.circle.fill" : "circle.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(showCircleOfFifths ? Theme.Color.accent : Theme.Color.secondaryText)
            .help("Toggle Circle of Fifths")

            // Detected chord display
            if viewModel.showChordDetection {
                if let chord = viewModel.detectedChord {
                    HStack(spacing: 4) {
                        Image(systemName: "guitars.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Color.accent)
                        Text(chord.name)
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("\(Int(viewModel.chordConfidence * 100))%")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Color.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("No chord")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

            // Live indicator
            if viewModel.isListening {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.activePitchClass != nil
                              ? Theme.Color.inTune
                              : Theme.Color.secondaryText.opacity(0.4))
                        .frame(width: 8, height: 8)
                    if let note = viewModel.activeNote {
                        Text(note.name(preferring: viewModel.accidental))
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Color.primaryText)
                            .monospacedDigit()
                    } else {
                        Text("Listening")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Scale info

    private var scaleInfoBar: some View {
        HStack(spacing: 12) {
            let pcs = viewModel.selectedScale.pitchClasses(in: viewModel.selectedRoot)
            ForEach(Array(pcs.enumerated()), id: \.offset) { index, pc in
                let degree = viewModel.scaleDegreeMap[pc] ?? ""
                VStack(spacing: 2) {
                    Text(degree)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text(pc.name(preferring: viewModel.accidental))
                        .font(Theme.Font.body.weight(.medium))
                        .foregroundStyle(
                            pc == viewModel.selectedRoot
                                ? Theme.Color.accent
                                : Theme.Color.primaryText
                        )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(pc == viewModel.activePitchClass
                              ? Theme.Color.accent.opacity(0.2)
                              : Color.clear)
                )
            }
            Spacer()
        }
    }
}

// MARK: - Canvas-drawn fretboard

/// Pure `Canvas` rendering of the fretboard. Strings run horizontally, frets
/// vertically, low E at the bottom (visual convention for tab/diagrams).
private struct FretboardCanvas: View {
    let viewModel: FretboardViewModel

    /// Layout constants
    private let nutWidth: CGFloat = 6
    private let stringSpacing: CGFloat = 28
    private let topPadding: CGFloat = 40   // room for fret numbers
    private let leftPadding: CGFloat = 40  // room for string labels
    private let dotRadius: CGFloat = 11
    private let fretInlays: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]
    private let doubleInlays: Set<Int> = [12]

    private var stringCount: Int { viewModel.fretboard.stringCount }
    private var fretCount: Int { viewModel.displayFretCount }

    private var neckHeight: CGFloat {
        CGFloat(stringCount - 1) * stringSpacing
    }

    var body: some View {
        Canvas { context, size in
            let neckWidth = size.width - leftPadding - 20
            let fretSpacings = fretSpacings(neckWidth: neckWidth)
            let yOrigin = topPadding
            let xOrigin = leftPadding

            drawNut(context: context, x: xOrigin, y: yOrigin)
            drawFrets(context: context, x: xOrigin, y: yOrigin, spacings: fretSpacings)
            drawStrings(context: context, x: xOrigin, y: yOrigin, neckWidth: neckWidth)
            drawInlays(context: context, x: xOrigin, y: yOrigin, spacings: fretSpacings)
            drawFretNumbers(context: context, x: xOrigin, y: yOrigin, spacings: fretSpacings)
            drawStringLabels(context: context, x: xOrigin, y: yOrigin)
            drawNotes(context: context, x: xOrigin, y: yOrigin, spacings: fretSpacings)
        }
        .frame(height: topPadding + neckHeight + 30)
    }

    // MARK: - Fret spacing (realistic: wider near nut, narrower near body)

    /// Returns cumulative X offsets for each fret (index 0 = fret 1's position).
    private func fretSpacings(neckWidth: CGFloat) -> [CGFloat] {
        // Real fret spacing: fret n is at scaleLength * (1 - 1/2^(n/12)).
        // We normalize to fill the available width.
        let rawPositions = (1...fretCount).map { n in
            1.0 - pow(2.0, -Double(n) / 12.0)
        }
        let maxRaw = rawPositions.last ?? 1
        let usableWidth = neckWidth - nutWidth
        return rawPositions.map { CGFloat($0 / maxRaw) * usableWidth }
    }

    /// X center of a fret position (between fret n-1 and fret n). Fret 0 = open (behind nut).
    private func fretCenterX(fret: Int, xOrigin: CGFloat, spacings: [CGFloat]) -> CGFloat {
        if fret == 0 {
            return xOrigin - 14  // open-string dot sits behind the nut
        }
        let xAfterNut = xOrigin + nutWidth
        let left = fret == 1 ? 0 : spacings[fret - 2]
        let right = spacings[fret - 1]
        return xAfterNut + (left + right) / 2
    }

    private func stringY(_ string: Int, yOrigin: CGFloat) -> CGFloat {
        // String 0 (low E) at bottom, string 5 (high E) at top — visual convention.
        yOrigin + CGFloat(stringCount - 1 - string) * stringSpacing
    }

    // MARK: - Drawing

    private func drawNut(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        let rect = CGRect(x: x, y: y - 2, width: nutWidth, height: neckHeight + 4)
        context.fill(Path(roundedRect: rect, cornerRadius: 2),
                     with: .color(.primary.opacity(0.8)))
    }

    private func drawFrets(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let xAfterNut = x + nutWidth
        for offset in spacings {
            let fx = xAfterNut + offset
            var path = Path()
            path.move(to: CGPoint(x: fx, y: y - 2))
            path.addLine(to: CGPoint(x: fx, y: y + neckHeight + 2))
            context.stroke(path, with: .color(.primary.opacity(0.2)), lineWidth: 1.5)
        }
    }

    private func drawStrings(context: GraphicsContext, x: CGFloat, y: CGFloat, neckWidth: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, yOrigin: y)
            // Thicker strings for lower pitches.
            let thickness: CGFloat = CGFloat(stringCount - s) * 0.4 + 0.6
            var path = Path()
            path.move(to: CGPoint(x: x, y: sy))
            path.addLine(to: CGPoint(x: x + neckWidth, y: sy))
            context.stroke(path, with: .color(.primary.opacity(0.35)), lineWidth: thickness)
        }
    }

    private func drawInlays(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let centerY = y + neckHeight / 2
        let inlayRadius: CGFloat = 4

        for fret in 1...fretCount where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, xOrigin: x, spacings: spacings)
            if doubleInlays.contains(fret) {
                // Double dot at 12th fret
                let offset = stringSpacing * 1.5
                context.fill(Circle().path(in: CGRect(
                    x: cx - inlayRadius, y: centerY - offset - inlayRadius,
                    width: inlayRadius * 2, height: inlayRadius * 2)),
                    with: .color(.primary.opacity(0.12)))
                context.fill(Circle().path(in: CGRect(
                    x: cx - inlayRadius, y: centerY + offset - inlayRadius,
                    width: inlayRadius * 2, height: inlayRadius * 2)),
                    with: .color(.primary.opacity(0.12)))
            } else {
                context.fill(Circle().path(in: CGRect(
                    x: cx - inlayRadius, y: centerY - inlayRadius,
                    width: inlayRadius * 2, height: inlayRadius * 2)),
                    with: .color(.primary.opacity(0.12)))
            }
        }
    }

    private func drawFretNumbers(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        for fret in 1...fretCount where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, xOrigin: x, spacings: spacings)
            let text = Text("\(fret)")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: CGPoint(x: cx, y: y - 16), anchor: .center)
        }
    }

    private func drawStringLabels(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, yOrigin: y)
            let note = viewModel.fretboard.tuning.openStrings[s]
            let label = note.pitchClass.name(preferring: viewModel.accidental)
            let text = Text(label)
                .font(Theme.Font.caption.weight(.medium))
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: CGPoint(x: x - 20, y: sy), anchor: .center)
        }
    }

    private func drawNotes(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let chordMode = viewModel.showChordDetection && viewModel.detectedChord != nil

        for s in 0..<stringCount {
            for f in 0...fretCount {
                guard viewModel.isInScale(string: s, fret: f) else { continue }

                let cx = fretCenterX(fret: f, xOrigin: x, spacings: spacings)
                let cy = stringY(s, yOrigin: y)
                let isRoot = viewModel.isRoot(string: s, fret: f)
                let isActive = viewModel.isActive(string: s, fret: f)
                let isChordTone = chordMode && viewModel.isChordTone(string: s, fret: f)
                let isChordRoot = chordMode && viewModel.isChordRoot(string: s, fret: f)
                let degree = viewModel.degreeLabel(string: s, fret: f) ?? ""

                // Dot color — chord tones get special treatment
                let fillColor: Color
                if isActive {
                    fillColor = Theme.Color.inTune
                } else if isChordRoot {
                    fillColor = Theme.Color.nearInTune
                } else if isChordTone {
                    fillColor = Theme.Color.nearInTune.opacity(0.6)
                } else if isRoot {
                    fillColor = Theme.Color.accent
                } else {
                    fillColor = Theme.Color.primaryText.opacity(chordMode ? 0.06 : 0.15)
                }

                // Dot
                let r: CGFloat
                if isActive {
                    r = dotRadius + 2
                } else if isChordTone || isChordRoot {
                    r = dotRadius + 1
                } else {
                    r = dotRadius
                }
                let dotRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: dotRect), with: .color(fillColor))

                // Outline for root notes or chord root
                if isChordRoot && !isActive {
                    context.stroke(Circle().path(in: dotRect),
                                   with: .color(Theme.Color.nearInTune),
                                   lineWidth: 2)
                } else if isRoot && !isActive {
                    context.stroke(Circle().path(in: dotRect),
                                   with: .color(Theme.Color.accent),
                                   lineWidth: 2)
                }

                // Degree label text
                let textColor: Color
                if isRoot || isActive || isChordTone || isChordRoot {
                    textColor = .white
                } else {
                    textColor = Theme.Color.primaryText.opacity(0.8)
                }
                let text = Text(degree)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                context.draw(text, at: CGPoint(x: cx, y: cy), anchor: .center)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FretboardView(detector: MockPitchDetector())
        .frame(width: 1000, height: 400)
}
