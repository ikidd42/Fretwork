import SwiftUI

/// Compact, static fretboard used as a hint overlay in flash cards.
/// Shows highlighted notes without live pitch detection — just a visual
/// reference so the player can find the right note on the neck.
struct HintFretboardView: View {
    let hint: FlashCardsViewModel.HintData
    let tuning: Tuning
    let accidental: Accidental

    private let fretboard: Fretboard
    private let displayFrets = 15

    init(hint: FlashCardsViewModel.HintData,
         tuning: Tuning = .standard,
         accidental: Accidental = .sharp) {
        self.hint = hint
        self.tuning = tuning
        self.accidental = accidental
        self.fretboard = Fretboard(tuning: tuning)
    }

    // Layout
    private let nutWidth: CGFloat = 4
    private let stringSpacing: CGFloat = 20
    private let topPadding: CGFloat = 24
    private let leftPadding: CGFloat = 28
    private let dotRadius: CGFloat = 8
    private let fretInlays: Set<Int> = [3, 5, 7, 9, 12, 15]
    private let doubleInlays: Set<Int> = [12]

    private var stringCount: Int { fretboard.stringCount }
    private var neckHeight: CGFloat { CGFloat(stringCount - 1) * stringSpacing }

    var body: some View {
        VStack(spacing: 6) {
            Text(hint.label)
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(Theme.Color.secondaryText)

            Canvas { context, size in
                let neckWidth = size.width - leftPadding - 12
                let spacings = fretSpacings(neckWidth: neckWidth)
                let y = topPadding
                let x = leftPadding

                drawNut(context: context, x: x, y: y)
                drawFrets(context: context, x: x, y: y, spacings: spacings)
                drawStrings(context: context, x: x, y: y, neckWidth: neckWidth)
                drawInlays(context: context, x: x, y: y, spacings: spacings)
                drawFretNumbers(context: context, x: x, y: y, spacings: spacings)
                drawStringLabels(context: context, x: x, y: y)
                drawNotes(context: context, x: x, y: y, spacings: spacings)
            }
            .frame(height: topPadding + neckHeight + 16)
        }
        .padding(12)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                .strokeBorder(Theme.Color.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Fret spacing

    private func fretSpacings(neckWidth: CGFloat) -> [CGFloat] {
        let rawPositions = (1...displayFrets).map { n in
            1.0 - pow(2.0, -Double(n) / 12.0)
        }
        let maxRaw = rawPositions.last ?? 1
        let usable = neckWidth - nutWidth
        return rawPositions.map { CGFloat($0 / maxRaw) * usable }
    }

    private func fretCenterX(fret: Int, x: CGFloat, spacings: [CGFloat]) -> CGFloat {
        if fret == 0 { return x - 10 }
        let xAfterNut = x + nutWidth
        let left = fret == 1 ? 0 : spacings[fret - 2]
        let right = spacings[fret - 1]
        return xAfterNut + (left + right) / 2
    }

    private func stringY(_ string: Int, y: CGFloat) -> CGFloat {
        y + CGFloat(stringCount - 1 - string) * stringSpacing
    }

    // MARK: - Drawing

    private func drawNut(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        let rect = CGRect(x: x, y: y - 1, width: nutWidth, height: neckHeight + 2)
        context.fill(Path(roundedRect: rect, cornerRadius: 1),
                     with: .color(.primary.opacity(0.7)))
    }

    private func drawFrets(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let xAfterNut = x + nutWidth
        for offset in spacings {
            var path = Path()
            path.move(to: CGPoint(x: xAfterNut + offset, y: y - 1))
            path.addLine(to: CGPoint(x: xAfterNut + offset, y: y + neckHeight + 1))
            context.stroke(path, with: .color(.primary.opacity(0.15)), lineWidth: 1)
        }
    }

    private func drawStrings(context: GraphicsContext, x: CGFloat, y: CGFloat, neckWidth: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, y: y)
            let thickness: CGFloat = CGFloat(stringCount - s) * 0.3 + 0.4
            var path = Path()
            path.move(to: CGPoint(x: x, y: sy))
            path.addLine(to: CGPoint(x: x + neckWidth, y: sy))
            context.stroke(path, with: .color(.primary.opacity(0.25)), lineWidth: thickness)
        }
    }

    private func drawInlays(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let centerY = y + neckHeight / 2
        let r: CGFloat = 3

        for fret in 1...displayFrets where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, x: x, spacings: spacings)
            if doubleInlays.contains(fret) {
                let offset = stringSpacing * 1.5
                for dy in [-offset, offset] {
                    context.fill(Circle().path(in: CGRect(
                        x: cx - r, y: centerY + dy - r, width: r * 2, height: r * 2)),
                        with: .color(.primary.opacity(0.08)))
                }
            } else {
                context.fill(Circle().path(in: CGRect(
                    x: cx - r, y: centerY - r, width: r * 2, height: r * 2)),
                    with: .color(.primary.opacity(0.08)))
            }
        }
    }

    private func drawFretNumbers(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        for fret in 1...displayFrets where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, x: x, spacings: spacings)
            let text = Text("\(fret)")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: CGPoint(x: cx, y: y - 10), anchor: .center)
        }
    }

    private func drawStringLabels(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, y: y)
            let label = tuning.openStrings[s].pitchClass.name(preferring: accidental)
            let text = Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: CGPoint(x: x - 14, y: sy), anchor: .center)
        }
    }

    private func drawNotes(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        for s in 0..<stringCount {
            for f in 0...displayFrets {
                let pc = fretboard.note(string: s, fret: f).pitchClass
                guard hint.scalePitchClasses.contains(pc) else { continue }

                let cx = fretCenterX(fret: f, x: x, spacings: spacings)
                let cy = stringY(s, y: y)
                let isTarget = hint.targetPitchClasses.contains(pc)
                let isRoot = pc == hint.root

                let fillColor: Color
                if isTarget && isRoot {
                    fillColor = Theme.Color.accent
                } else if isTarget {
                    fillColor = Theme.Color.inTune
                } else if isRoot {
                    fillColor = Theme.Color.accent.opacity(0.6)
                } else {
                    fillColor = Theme.Color.primaryText.opacity(0.12)
                }

                let r = isTarget ? dotRadius + 1 : dotRadius
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(fillColor))

                // Label
                let label = hint.degreeMap[pc] ?? pc.name(preferring: accidental)
                let textColor: Color = (isTarget || isRoot) ? .white : Theme.Color.primaryText.opacity(0.7)
                let text = Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                context.draw(text, at: CGPoint(x: cx, y: cy), anchor: .center)
            }
        }
    }
}
