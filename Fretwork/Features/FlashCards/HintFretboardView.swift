import SwiftUI

/// Compact, static fretboard used as a hint overlay in flash cards.
/// Shows highlighted notes without live pitch detection — just a visual
/// reference so the player can find the right note on the neck.
///
/// Drawn with the same materials as the main fretboard (indigo ebony,
/// pearl nut and inlays) at a smaller scale; targets glow mint, roots wear
/// the accent, and everything else sits back as pearl ghosts.
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
    private let nutWidth: CGFloat = 5
    private let stringSpacing: CGFloat = 20
    private let topPadding: CGFloat = 26
    private let leftPadding: CGFloat = 40
    private let dotRadius: CGFloat = 8
    private let fretInlays: Set<Int> = [3, 5, 7, 9, 12, 15]
    private let doubleInlays: Set<Int> = [12]

    private var stringCount: Int { fretboard.stringCount }
    private var neckHeight: CGFloat { CGFloat(stringCount - 1) * stringSpacing }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                MicroLabel("Hint")
                Text(hint.label)
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundStyle(Theme.Color.secondaryText)
                Spacer()
            }

            Canvas { context, size in
                let neckWidth = size.width - leftPadding - 16
                let spacings = fretSpacings(neckWidth: neckWidth)
                let y = topPadding
                let x = leftPadding

                drawNeck(context: context, x: x, y: y, neckWidth: neckWidth)
                drawInlays(context: context, x: x, y: y, spacings: spacings)
                drawNut(context: context, x: x, y: y)
                drawFrets(context: context, x: x, y: y, spacings: spacings)
                drawStrings(context: context, x: x, y: y, neckWidth: neckWidth)
                drawFretNumbers(context: context, x: x, y: y, spacings: spacings)
                drawStringLabels(context: context, x: x, y: y)
                drawNotes(context: context, x: x, y: y, spacings: spacings)
            }
            .frame(height: topPadding + neckHeight + 18)
        }
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous)
                .strokeBorder(Theme.Color.accent.opacity(0.28), lineWidth: 1)
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
        if fret == 0 { return x - 12 }
        let xAfterNut = x + nutWidth
        let left = fret == 1 ? 0 : spacings[fret - 2]
        let right = spacings[fret - 1]
        return xAfterNut + (left + right) / 2
    }

    private func stringY(_ string: Int, y: CGFloat) -> CGFloat {
        y + CGFloat(stringCount - 1 - string) * stringSpacing
    }

    // MARK: - Drawing

    private func drawNeck(context: GraphicsContext, x: CGFloat, y: CGFloat, neckWidth: CGFloat) {
        let rect = CGRect(x: x - 26, y: y - 11, width: neckWidth + 26 + 10, height: neckHeight + 22)
        let neckPath = Path(roundedRect: rect, cornerRadius: 8, style: .continuous)
        context.fill(neckPath, with: .linearGradient(
            Gradient(colors: [Theme.Color.neckTop, Theme.Color.neckBottom]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.minX, y: rect.maxY)
        ))
        context.stroke(neckPath, with: .color(.white.opacity(0.09)), lineWidth: 1)
    }

    private func drawNut(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        let rect = CGRect(x: x, y: y - 2, width: nutWidth, height: neckHeight + 4)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .linearGradient(
                Gradient(colors: Pearlescent.bandColors),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
    }

    private func drawFrets(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let xAfterNut = x + nutWidth
        for offset in spacings {
            var path = Path()
            path.move(to: CGPoint(x: xAfterNut + offset, y: y - 1))
            path.addLine(to: CGPoint(x: xAfterNut + offset, y: y + neckHeight + 1))
            context.stroke(path, with: .color(Theme.Color.sidebarString.opacity(0.22)), lineWidth: 1)
        }
    }

    private func drawStrings(context: GraphicsContext, x: CGFloat, y: CGFloat, neckWidth: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, y: y)
            let thickness: CGFloat = CGFloat(stringCount - s) * 0.3 + 0.4
            var path = Path()
            path.move(to: CGPoint(x: x - 22, y: sy))
            path.addLine(to: CGPoint(x: x + neckWidth + 6, y: sy))
            context.stroke(path, with: .color(Theme.Color.sidebarString.opacity(0.38)), lineWidth: thickness)
        }
    }

    private func drawInlays(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        let centerY = y + neckHeight / 2
        let r: CGFloat = 3.5

        for fret in 1...displayFrets where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, x: x, spacings: spacings)
            if doubleInlays.contains(fret) {
                let offset = stringSpacing * 1.5
                for dy in [-offset, offset] {
                    drawPearlInlay(context: context, at: CGPoint(x: cx, y: centerY + dy), radius: r)
                }
            } else {
                drawPearlInlay(context: context, at: CGPoint(x: cx, y: centerY), radius: r)
            }
        }
    }

    private func drawPearlInlay(context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(
            Circle().path(in: rect),
            with: .linearGradient(
                Gradient(colors: Pearlescent.bandColors.map { $0.opacity(0.5) }),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
    }

    private func drawFretNumbers(context: GraphicsContext, x: CGFloat, y: CGFloat, spacings: [CGFloat]) {
        for fret in 1...displayFrets where fretInlays.contains(fret) {
            let cx = fretCenterX(fret: fret, x: x, spacings: spacings)
            let text = Text("\(fret)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Color.tertiaryText)
            context.draw(text, at: CGPoint(x: cx, y: y - 16), anchor: .center)
        }
    }

    private func drawStringLabels(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        for s in 0..<stringCount {
            let sy = stringY(s, y: y)
            let label = tuning.openStrings[s].pitchClass.name(preferring: accidental)
            let text = Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Color.secondaryText)
            context.draw(text, at: CGPoint(x: x - 32, y: sy), anchor: .center)
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

                // Glow under targets.
                if isTarget {
                    let glowR = r + 5
                    context.fill(
                        Circle().path(in: CGRect(x: cx - glowR, y: cy - glowR,
                                                 width: glowR * 2, height: glowR * 2)),
                        with: .color((isRoot ? Theme.Color.accent : Theme.Color.inTune).opacity(0.18))
                    )
                }

                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(fillColor))

                // Label
                let label = hint.degreeMap[pc] ?? pc.name(preferring: accidental)
                let textColor: Color = (isTarget || isRoot)
                    ? Theme.Color.onAccent
                    : Theme.Color.primaryText.opacity(0.7)
                let text = Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                context.draw(text, at: CGPoint(x: cx, y: cy), anchor: .center)
            }
        }
    }
}
