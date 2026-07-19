import SwiftUI
import Combine

/// Tuner: a "halo" gauge around the detected note.
///
/// The gauge arc carries the tuning zones (green center through red edges),
/// a needle tracks cents-off with a spring, and the panel behind breathes
/// with the tuning color — the whole stage light changes as you dial in.
/// Below: per-string targets for standard tuning and a signal strip with
/// the input level (dB) and a scrolling stability trail.
struct TunerView: View {
    @State private var viewModel: TunerViewModel

    /// Scrolling cents history for the stability trail (nil = silence gap).
    @State private var centsTrail: [Double?] = []
    private let trailCapacity = 110
    /// 30 Hz sampling keeps the trail scrolling smoothly even when the
    /// detector's EMA settles and stops emitting distinct values.
    private let trailTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(detector: any PitchDetector) {
        _viewModel = State(wrappedValue: TunerViewModel(detector: detector))
    }

    private var isActive: Bool { viewModel.smoothedNote != nil }
    private var isLocked: Bool { isActive && abs(viewModel.smoothedCentsOff) < 5 }

    var body: some View {
        VStack(spacing: 0) {
            permissionBanner

            Spacer(minLength: 8)

            HaloGauge(
                note: viewModel.smoothedNote,
                centsOff: viewModel.smoothedCentsOff,
                frequency: viewModel.smoothedFrequency,
                isLocked: isLocked
            )
            .frame(maxWidth: 360, maxHeight: 360)

            Spacer(minLength: 12)

            StringTargetStrip(
                note: viewModel.smoothedNote,
                frequency: viewModel.smoothedFrequency
            )

            Spacer(minLength: 12)

            signalStrip
        }
        .padding(Theme.Metrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onReceive(trailTimer) { _ in
            centsTrail.append(isActive ? viewModel.smoothedCentsOff : nil)
            if centsTrail.count > trailCapacity {
                centsTrail.removeFirst(centsTrail.count - trailCapacity)
            }
        }
    }

    // MARK: - Signal strip (input level + stability)

    private var signalStrip: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MicroLabel("Input")
                    Spacer()
                    Text(decibelsDisplay)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Color.tertiaryText)
                        .monospacedDigit()
                }
                InputLevelMeter(
                    level: viewModel.inputLevel,
                    threshold: viewModel.amplitudeThreshold
                )
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.Color.hairline)
                .frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MicroLabel("Stability")
                    Spacer()
                    Text("±50¢")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
                StabilityTrail(samples: centsTrail)
                    .frame(height: 34)
            }
            .frame(maxWidth: .infinity)
        }
        .stageCard(padding: 16)
    }

    private var decibelsDisplay: String {
        let db = 20 * log10(max(viewModel.inputLevel, 0.00001))
        return String(format: "%.0f dB", db)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        switch viewModel.permission {
        case .denied:
            Banner(
                text: "Microphone access denied. Enable Fretwork in System Settings → Privacy & Security → Microphone.",
                tint: Theme.Color.farOutOfTune
            )
            .padding(.bottom, 8)
        case .undetermined, .granted:
            if let error = viewModel.lastError {
                Banner(text: error, tint: Theme.Color.outOfTune)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Halo gauge

/// The tuner's hero: a 240° arc with the tuning zones baked in as an angular
/// gradient, tick marks every 5¢, a spring-loaded needle, and the detected
/// note at the center. When the pitch locks (±5¢), the arc blooms green.
private struct HaloGauge: View {
    let note: Note?
    let centsOff: Double
    /// Smoothed input frequency, shown beneath the cents readout.
    let frequency: Double?
    let isLocked: Bool

    /// Gauge spans ±50¢ over 240°, from 150° through the top to 30°.
    /// (SwiftUI angles: 0° east, 90° south, 270° north — y grows down.)
    private let range: Double = 50

    private var isActive: Bool { note != nil }
    private var tuningColor: Color { Theme.Color.tuningColor(centsOff: centsOff) }
    /// Needle rotation around the center; 0° = straight up (in tune).
    private var needleAngle: Angle {
        let clamped = max(-range, min(range, centsOff))
        return .degrees(clamped / range * 120)
    }

    /// Zone boundaries along the 240° sweep, red at both ends → green center.
    private static let zoneStops: [Gradient.Stop] = {
        let red = Theme.Color.farOutOfTune
        let orange = Theme.Color.outOfTune
        let yellow = Theme.Color.nearInTune
        let green = Theme.Color.inTune
        return [
            .init(color: red, location: 0.00),
            .init(color: red, location: 0.18),
            .init(color: orange, location: 0.22),
            .init(color: orange, location: 0.33),
            .init(color: yellow, location: 0.37),
            .init(color: yellow, location: 0.44),
            .init(color: green, location: 0.47),
            .init(color: green, location: 0.53),
            .init(color: yellow, location: 0.56),
            .init(color: yellow, location: 0.63),
            .init(color: orange, location: 0.67),
            .init(color: orange, location: 0.78),
            .init(color: red, location: 0.82),
            .init(color: red, location: 1.00),
        ]
    }()

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let arcRadius = side / 2 - 26

            ZStack {
                // Ambient stage light: breathes with the tuning color.
                RadialGradient(
                    colors: [
                        (isActive ? tuningColor : Theme.Color.accent)
                            .opacity(isLocked ? 0.16 : (isActive ? 0.09 : 0.05)),
                        .clear
                    ],
                    center: .center,
                    startRadius: arcRadius * 0.2,
                    endRadius: side * 0.72
                )
                .animation(.easeInOut(duration: 0.3), value: isLocked)

                zoneArc(radius: arcRadius)
                tickMarks(radius: arcRadius)

                if isActive {
                    needle(radius: arcRadius)
                }

                centerReadout
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The colored tuning-zone band, drawn as a trimmed circle stroke so an
    /// AngularGradient can paint it (Canvas strokes can't shade angularly).
    private func zoneArc(radius: CGFloat) -> some View {
        ZStack {
            // Bloom: soft green halo bleeding outward when locked in.
            Circle()
                .trim(from: 0, to: 240.0 / 360.0)
                .rotation(.degrees(150))
                .stroke(Theme.Color.inTune.opacity(isLocked ? 0.22 : 0),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round))
                .blur(radius: 10)

            Circle()
                .trim(from: 0, to: 240.0 / 360.0)
                .rotation(.degrees(150))
                .stroke(
                    AngularGradient(
                        stops: Self.zoneStops,
                        center: .center,
                        startAngle: .degrees(150),
                        endAngle: .degrees(390)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .butt)
                )
                .opacity(isActive ? 0.85 : 0.30)
        }
        .frame(width: radius * 2, height: radius * 2)
        .animation(.easeInOut(duration: 0.25), value: isLocked)
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    /// Tick marks every 5¢ (longer and brighter each 25¢), plus end labels.
    private func tickMarks(radius: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for cents in stride(from: -50, through: 50, by: 5) {
                let isMajor = cents % 25 == 0
                let angle = Angle.degrees(270 + Double(cents) / 50 * 120).radians
                let inner = radius - (isMajor ? 2 : 4)
                let outer = radius + (isMajor ? 13 : 8)

                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + inner * cos(angle),
                    y: center.y + inner * sin(angle)
                ))
                path.addLine(to: CGPoint(
                    x: center.x + outer * cos(angle),
                    y: center.y + outer * sin(angle)
                ))
                context.stroke(
                    path,
                    with: .color(.white.opacity(isMajor ? 0.42 : 0.16)),
                    style: StrokeStyle(lineWidth: isMajor ? 2 : 1, lineCap: .round)
                )
            }

            // End-of-scale labels, tucked just outside the arc's open ends.
            for (cents, label) in [(-50, "50"), (50, "50")] {
                let angle = Angle.degrees(270 + Double(cents) / 50 * 120).radians
                let labelR = radius + 24
                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Color.tertiaryText)
                context.draw(text, at: CGPoint(
                    x: center.x + labelR * cos(angle),
                    y: center.y + labelR * sin(angle)
                ), anchor: .center)
            }

            // "0" sits above the arc's crown.
            let zero = Text("0")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Color.tertiaryText)
            context.draw(zero, at: CGPoint(x: center.x, y: center.y - radius - 16), anchor: .center)
        }
    }

    /// Spring-loaded needle with a glowing tip, pivoted about the gauge
    /// center (the capsule and its tip ride one rotating stack).
    private func needle(radius: CGFloat) -> some View {
        let innerGap = radius * 0.58
        let length = radius * 0.26

        return ZStack {
            Capsule()
                .fill(Theme.Color.inlay.opacity(0.9))
                .frame(width: 3.5, height: length)
                .offset(y: -(innerGap + length / 2))

            Circle()
                .fill(tuningColor)
                .frame(width: 10, height: 10)
                .shadow(color: tuningColor.opacity(0.9), radius: 6)
                .offset(y: -(innerGap + length))
        }
        .rotationEffect(needleAngle)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: centsOff)
    }

    /// Note letter + octave, cents readout, and frequency — the gauge core.
    private var centerReadout: some View {
        VStack(spacing: 0) {
            if let note {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(note.pitchClass.sharpName)
                        .font(Theme.Font.haloNote)
                        .foregroundStyle(tuningColor)
                    Text("\(note.octave)")
                        .font(Theme.Font.haloOctave)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .shadow(color: tuningColor.opacity(isLocked ? 0.55 : 0.0), radius: 18)

                Text(centsDisplay)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tuningColor)
                    .monospacedDigit()
                    .padding(.top, 2)

                Text(frequencyDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .monospacedDigit()
                    .padding(.top, 4)
            } else {
                // Idle: the biggest glyph in the app gets the full pearl
                // treatment while it waits. Once a note lands, functional
                // tuning color takes over.
                Text("—")
                    .font(Theme.Font.haloNote)
                    .pearlShimmer()

                Text("PLAY A NOTE")
                    .font(Theme.Font.microLabel)
                    .tracking(1.6)
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .padding(.top, 6)
            }
        }
        .animation(.snappy(duration: 0.15), value: note)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }

    private var centsDisplay: String {
        let cents = Int(centsOff.rounded())
        return cents >= 0 ? "+\(cents)¢" : "\(cents)¢"
    }

    private var frequencyDisplay: String {
        guard let frequency else { return "" }
        return String(format: "%.1f Hz", frequency)
    }
}

// MARK: - Per-string targets

/// The six open strings of standard tuning as tappable-glance chips: the
/// string nearest the detected note lights mint, and turns green with a
/// glow once it's within ±5¢ of its open pitch.
private struct StringTargetStrip: View {
    let note: Note?
    /// Smoothed input frequency, for per-string cents readouts.
    let frequency: Double?

    private let strings = Tuning.standard.openStrings

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(strings.enumerated()), id: \.offset) { _, open in
                stringChip(open)
            }
        }
    }

    private func stringChip(_ open: Note) -> some View {
        // Full-note match (pitch class AND octave) so an E only lights the
        // E string it's actually near, not both E chips at once.
        let isTarget = note == open
        let cents = stringCents(to: open)
        let locked = isTarget && cents.map { abs($0) < 5 } == true

        return VStack(spacing: 1) {
            Text(open.pitchClass.sharpName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(isTarget && cents != nil ? centsLabel(cents!) : "·\(open.octave)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(
            locked ? Theme.Color.inTune
                : isTarget ? Theme.Color.accent
                : Theme.Color.tertiaryText
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            (locked ? Theme.Color.inTune.opacity(0.16)
                : isTarget ? Theme.Color.accentSoft
                : Theme.Color.surface),
            in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
                .strokeBorder(
                    locked ? Theme.Color.inTune.opacity(0.55)
                        : isTarget ? Theme.Color.accent.opacity(0.45)
                        : Theme.Color.hairline,
                    lineWidth: 1
                )
        )
        .shadow(color: locked ? Theme.Color.inTune.opacity(0.35) : .clear, radius: 8)
        .animation(.snappy(duration: 0.18), value: isTarget)
        .animation(.easeInOut(duration: 0.2), value: locked)
    }

    /// Cents between the live frequency and this string's open pitch.
    private func stringCents(to open: Note) -> Double? {
        guard let frequency, frequency > 0 else { return nil }
        let cents = 1200 * log2(frequency / open.frequency)
        return abs(cents) <= 120 ? cents : nil
    }

    private func centsLabel(_ cents: Double) -> String {
        let c = Int(cents.rounded())
        return c >= 0 ? "+\(c)¢" : "\(c)¢"
    }
}

// MARK: - Input level meter

/// dB-scaled input meter with a marker at the amplitude gate — the player
/// can see a quiet pluck dying *before* the tuner stops hearing it.
private struct InputLevelMeter: View {
    let level: Double
    let threshold: Double

    /// Meter spans −60…0 dB.
    private func fraction(of amplitude: Double) -> CGFloat {
        let db = 20 * log10(max(amplitude, 0.00001))
        return CGFloat(max(0, min(1, (db + 60) / 60)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.track)

                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.Color.accentDeep, Theme.Color.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(6, geo.size.width * fraction(of: level)))
                    .animation(.easeOut(duration: 0.08), value: level)

                // Amplitude gate marker.
                Rectangle()
                    .fill(Theme.Color.marker)
                    .frame(width: 1.5)
                    .offset(x: geo.size.width * fraction(of: threshold))
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: - Stability trail

/// Scrolling history of cents-off: each column is one sample, colored by
/// how far from center it was. A calm performance draws a flat green line.
private struct StabilityTrail: View {
    let samples: [Double?]

    var body: some View {
        Canvas { context, size in
            // Center hairline.
            var center = Path()
            center.move(to: CGPoint(x: 0, y: size.height / 2))
            center.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(center, with: .color(.white.opacity(0.18)), lineWidth: 1)

            guard !samples.isEmpty else { return }
            let step = size.width / CGFloat(samples.count)
            let barWidth = max(1, step - 1)
            let halfHeight = size.height / 2 - 1

            for (index, sample) in samples.enumerated() {
                guard let cents = sample else { continue }
                let clamped = max(-50, min(50, cents))
                let height = max(1.5, CGFloat(abs(clamped) / 50) * halfHeight)
                let x = CGFloat(index) * step
                let rect = CGRect(
                    x: x,
                    y: size.height / 2 - height,
                    width: barWidth,
                    height: height * 2
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(Theme.Color.tuningColor(centsOff: clamped).opacity(0.75))
                )
            }
        }
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview {
    TunerView(detector: MockPitchDetector())
        .frame(width: 760, height: 640)
}
