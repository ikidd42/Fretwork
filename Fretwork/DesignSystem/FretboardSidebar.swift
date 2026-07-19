import SwiftUI

/// The app sidebar, drawn as a fretboard — the same visual identity as the
/// app icon: deep indigo board, six strings running down it, sections
/// separated by frets, and the selected section marked with a glowing
/// cream inlay dot.
///
/// Deliberately a fixed dark surface in both light and dark appearance:
/// it's the brand element, and the detail pane stays semantic.
struct FretboardSidebar: View {
    @Binding var selection: AppSection?
    @State private var hovered: AppSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the mother-of-pearl sheen across every inlay in sync
    /// (with small per-row offsets). One slow cycle; see `Pearlescent`.
    @State private var pearlPhase: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            // The nut sits under the headstock, like on the instrument.
            nut

            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                row(section, index: index)
                fret
            }

            Spacer(minLength: 0)
        }
        .background(board)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                pearlPhase = 1
            }
        }
    }

    // MARK: - Board

    private var board: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Color.sidebarTop, Theme.Color.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            strings
        }
        .ignoresSafeArea()
    }

    /// Six vertical strings, wound (thicker, dimmer) to plain (thinner,
    /// brighter), faint enough to read labels over.
    private var strings: some View {
        Canvas { context, size in
            let count = 6
            let inset: CGFloat = 18
            let gap = (size.width - inset * 2) / CGFloat(count - 1)
            for i in 0..<count {
                let x = inset + CGFloat(i) * gap
                let width = 2.6 - CGFloat(i) * 0.35
                let opacity = 0.08 + Double(i) * 0.012
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(Theme.Color.sidebarString.opacity(opacity)),
                    lineWidth: width
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var nut: some View {
        // The nut is bone on a real guitar — pearl suits it here.
        RoundedRectangle(cornerRadius: 2)
            .pearlescent(phase: pearlPhase, offset: 0.03)
            .frame(height: 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    private var fret: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Theme.Color.sidebarString.opacity(0.16))
            .frame(height: 1.5)
            .padding(.horizontal, 10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "guitars.fill")
                .font(.system(size: 19, weight: .semibold))
            Text("Fretwork")
                .font(.system(size: 19, design: .rounded).weight(.semibold))
                .tracking(3)
        }
        .pearlescent(phase: pearlPhase)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 15)
    }

    // MARK: - Rows

    private func row(_ section: AppSection, index: Int) -> some View {
        let isSelected = selection == section
        let isHovered = hovered == section
        // The sheen arrives at each row a beat after the one above,
        // like light traveling down the board.
        let rowOffset = 0.06 * Double(index + 1)

        return Button {
            selection = section
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    // Inlay dot: pearl for the selected section, a faint
                    // position-marker ghost otherwise.
                    if isSelected {
                        Circle()
                            .pearlescent(phase: pearlPhase, offset: rowOffset)
                            .frame(width: 34, height: 34)
                            .shadow(color: Theme.Color.inlay.opacity(0.65), radius: 9)
                    } else {
                        Circle()
                            .fill(Theme.Color.sidebarString.opacity(isHovered ? 0.16 : 0.10))
                            .frame(width: 34, height: 34)
                    }
                    Image(systemName: section.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(Theme.Color.sidebarBottom)
                                : AnyShapeStyle(Pearlescent.bandGradient(intensity: 0.72))
                        )
                }
                Text(section.title)
                    .font(.system(size: 16, design: .rounded).weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                    .pearlescent(
                        phase: pearlPhase,
                        offset: rowOffset,
                        intensity: isSelected ? 1 : 0.72
                    )
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusInner, style: .continuous)
                    .fill(Theme.Color.sidebarString.opacity(isHovered && !isSelected ? 0.07 : 0))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? section : (hovered == section ? nil : hovered)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection: AppSection? = .tuner
    return FretboardSidebar(selection: $selection)
        .frame(width: 210, height: 480)
}
