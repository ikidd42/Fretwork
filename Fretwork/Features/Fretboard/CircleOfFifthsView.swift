import SwiftUI

/// Interactive circle of fifths drawn as two concentric rings: major keys on the
/// outer ring, their relative minors on the inner ring. The selected key is
/// highlighted, and tapping any segment updates the key.
///
/// Layout: 12 segments, starting at 12-o'clock with C, moving clockwise by
/// fifths: C–G–D–A–E–B–F♯/G♭–D♭–A♭–E♭–B♭–F.
struct CircleOfFifthsView: View {
    @Binding var selectedRoot: PitchClass
    let accidental: Accidental
    let activePitchClass: PitchClass?
    let scalePitchClasses: Set<PitchClass>

    /// Circle of fifths order starting at C (12 o'clock), clockwise.
    private static let majorOrder: [PitchClass] = [
        .c, .g, .d, .a, .e, .b, .fSharp, .cSharp, .gSharp, .dSharp, .aSharp, .f
    ]

    /// Relative minor for each major key (3 semitones below).
    private static func relativeMinor(of major: PitchClass) -> PitchClass {
        major.transposed(by: -3)
    }

    /// How many sharps (positive) or flats (negative) in the key signature.
    private static let signatureCounts: [PitchClass: Int] = [
        .c: 0, .g: 1, .d: 2, .a: 3, .e: 4, .b: 5,
        .fSharp: 6, .cSharp: 7,
        .f: -1, .aSharp: -2, .dSharp: -3, .gSharp: -4
    ]

    var body: some View {
        VStack(spacing: 8) {
            keyLabel
            circleCanvas
            legend
        }
    }

    // MARK: - Key label

    private var keyLabel: some View {
        VStack(spacing: 2) {
            Text("\(selectedRoot.name(preferring: accidental)) Major")
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.Color.primaryText)

            let rm = Self.relativeMinor(of: selectedRoot)
            Text("Relative minor: \(rm.name(preferring: accidental))m")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    // MARK: - Canvas

    private var circleCanvas: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            let outerR = size / 2 - 4
            let midR = outerR * 0.68
            let innerR = outerR * 0.42

            Canvas { context, _ in
                drawOuterRing(context: context, center: center, outer: outerR, inner: midR)
                drawInnerRing(context: context, center: center, outer: midR, inner: innerR)
                drawCenterDisc(context: context, center: center, radius: innerR)
            }
            .overlay {
                // SwiftUI overlay for hit-testable tap targets.
                circleOverlay(center: center, outerR: outerR, midR: midR, innerR: innerR)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Outer ring (major keys)

    private func drawOuterRing(context: GraphicsContext, center: CGPoint, outer: CGFloat, inner: CGFloat) {
        let segAngle = 2 * Double.pi / 12

        for (i, pc) in Self.majorOrder.enumerated() {
            let startAngle = segAngle * Double(i) - Double.pi / 2 - segAngle / 2
            let endAngle = startAngle + segAngle

            let path = segmentPath(center: center, outerR: outer, innerR: inner,
                                   start: startAngle, end: endAngle)

            // Fill
            let fill = segmentColor(for: pc, isMinor: false)
            context.fill(path, with: .color(fill))

            // Stroke
            context.stroke(path, with: .color(Theme.Color.background), lineWidth: 1.5)

            // Label
            let labelR = Double((outer + inner) / 2)
            let midAngle = (startAngle + endAngle) / 2
            let labelPt = CGPoint(
                x: Double(center.x) + labelR * cos(midAngle),
                y: Double(center.y) + labelR * sin(midAngle)
            )
            let name = displayName(for: pc, isMinor: false)
            let isSelected = pc == selectedRoot
            let text = Text(name)
                .font(.system(size: isSelected ? 14 : 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : Theme.Color.primaryText)
            context.draw(text, at: labelPt, anchor: .center)
        }
    }

    // MARK: - Inner ring (relative minors)

    private func drawInnerRing(context: GraphicsContext, center: CGPoint, outer: CGFloat, inner: CGFloat) {
        let segAngle = 2 * Double.pi / 12

        for (i, majorPC) in Self.majorOrder.enumerated() {
            let minorPC = Self.relativeMinor(of: majorPC)
            let startAngle = segAngle * Double(i) - Double.pi / 2 - segAngle / 2
            let endAngle = startAngle + segAngle

            let path = segmentPath(center: center, outerR: outer, innerR: inner,
                                   start: startAngle, end: endAngle)

            let fill = segmentColor(for: minorPC, isMinor: true)
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(Theme.Color.background), lineWidth: 1.5)

            let labelR = Double((outer + inner) / 2)
            let midAngle = (startAngle + endAngle) / 2
            let labelPt = CGPoint(
                x: Double(center.x) + labelR * cos(midAngle),
                y: Double(center.y) + labelR * sin(midAngle)
            )
            let relMinorOfSelected = Self.relativeMinor(of: selectedRoot)
            let isSelected = minorPC == relMinorOfSelected
            let name = "\(minorPC.name(preferring: accidental))m"
            let text = Text(name)
                .font(.system(size: isSelected ? 12 : 10, weight: isSelected ? .bold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .white : Theme.Color.primaryText.opacity(0.8))
            context.draw(text, at: labelPt, anchor: .center)
        }
    }

    // MARK: - Center disc

    private func drawCenterDisc(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Circle().path(in: rect), with: .color(Theme.Color.surface))
        context.stroke(Circle().path(in: rect), with: .color(.primary.opacity(0.1)), lineWidth: 1)

        // Show signature count in center
        if let count = Self.signatureCounts[selectedRoot] {
            let sigText: String
            if count == 0 {
                sigText = "No ♯/♭"
            } else if count > 0 {
                sigText = "\(count)♯"
            } else {
                sigText = "\(abs(count))♭"
            }
            let text = Text(sigText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: center, anchor: .center)
        }
    }

    // MARK: - Tap overlay

    private func circleOverlay(center: CGPoint, outerR: CGFloat, midR: CGFloat, innerR: CGFloat) -> some View {
        ZStack {
            // Outer ring taps (major keys)
            ForEach(Array(Self.majorOrder.enumerated()), id: \.element) { i, pc in
                segmentTapTarget(index: i, center: center, outerR: outerR, innerR: midR)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedRoot = pc
                        }
                    }
            }
            // Inner ring taps (minor → sets the relative major)
            ForEach(Array(Self.majorOrder.enumerated()), id: \.element) { i, majorPC in
                segmentTapTarget(index: i, center: center, outerR: midR, innerR: innerR)
                    .onTapGesture {
                        // Tapping a minor key selects its relative major
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedRoot = majorPC
                        }
                    }
            }
        }
    }

    private func segmentTapTarget(index: Int, center: CGPoint, outerR: CGFloat, innerR: CGFloat) -> some View {
        let segAngle = 2 * Double.pi / 12
        let startAngle = segAngle * Double(index) - Double.pi / 2 - segAngle / 2
        let endAngle = startAngle + segAngle
        let path = segmentPath(center: center, outerR: outerR, innerR: innerR,
                               start: startAngle, end: endAngle)
        return path.fill(Color.clear).contentShape(path)
    }

    // MARK: - Helpers

    private func segmentPath(center: CGPoint, outerR: CGFloat, innerR: CGFloat,
                             start: Double, end: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: outerR,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addArc(center: center, radius: innerR,
                    startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }

    private func segmentColor(for pc: PitchClass, isMinor: Bool) -> Color {
        let relMinor = Self.relativeMinor(of: selectedRoot)

        if !isMinor && pc == selectedRoot {
            return Theme.Color.accent
        }
        if isMinor && pc == relMinor {
            return Theme.Color.accent.opacity(0.7)
        }
        // Highlight notes that are in the current scale
        if scalePitchClasses.contains(pc) {
            return Theme.Color.accent.opacity(0.15)
        }
        // Currently played note
        if let active = activePitchClass, pc == active {
            return Theme.Color.inTune.opacity(0.3)
        }

        return isMinor
            ? Theme.Color.surface.opacity(0.6)
            : Theme.Color.surface
    }

    /// Display name, using flats for the flat-side keys (F through Db).
    private func displayName(for pc: PitchClass, isMinor: Bool) -> String {
        // Flat-side keys traditionally use flat names
        let flatKeys: Set<PitchClass> = [.f, .aSharp, .dSharp, .gSharp, .cSharp]
        let prefer: Accidental = flatKeys.contains(pc) ? .flat : accidental
        let name = pc.name(preferring: prefer)
        return isMinor ? "\(name)m" : name
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Theme.Color.accent, label: "Selected key")
            legendItem(color: Theme.Color.accent.opacity(0.15), label: "In scale")
            if activePitchClass != nil {
                legendItem(color: Theme.Color.inTune.opacity(0.3), label: "Playing")
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Color.secondaryText)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var root: PitchClass = .c

        var body: some View {
            CircleOfFifthsView(
                selectedRoot: $root,
                accidental: .sharp,
                activePitchClass: .g,
                scalePitchClasses: Set(Scale.major.pitchClasses(in: .c))
            )
            .frame(width: 320, height: 380)
            .padding()
        }
    }

    return PreviewWrapper()
}
