import SwiftUI

/// A looping animation that visualizes the product's core action: a dense
/// field of model "weight" blocks continuously collapsing into fewer,
/// denser, glowing blocks — then resetting. Used behind the auth brand
/// panel so the very first thing a user sees reflects what the app does,
/// not a generic gradient.
///
/// Deliberately built from plain shapes driven by `TimelineView(.animation)`
/// rather than a Lottie/video asset: it's cheap, resolution-independent,
/// and respects Reduce Motion automatically.
struct CompressionAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = 8
    private let rows = 10
    private let cycleDuration: Double = 4.5

    var body: some View {
        if reduceMotion {
            staticLattice
        } else {
            TimelineView(.animation) { context in
                Canvas { graphicsContext, size in
                    draw(in: &graphicsContext, size: size, date: context.date)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var staticLattice: some View {
        Canvas { graphicsContext, size in
            draw(in: &graphicsContext, size: size, phase: 0.55)
        }
        .allowsHitTesting(false)
    }

    private func draw(in graphicsContext: inout GraphicsContext, size: CGSize, date: Date) {
        let phase = (date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
        draw(in: &graphicsContext, size: size, phase: phase)
    }

    /// `phase` runs 0...1 across one loop:
    ///   0.00–0.55  full-resolution lattice drifts gently ("fp16 weights")
    ///   0.55–0.85  blocks collapse pairwise into a sparser, brighter grid ("quantize")
    ///   0.85–1.00  hold, then fade back to the full lattice
    private func draw(in graphicsContext: inout GraphicsContext, size: CGSize, phase: Double) {
        let collapseStart = 0.55
        let collapseEnd = 0.85
        let collapse: Double
        if phase < collapseStart {
            collapse = 0
        } else if phase < collapseEnd {
            collapse = easeInOut((phase - collapseStart) / (collapseEnd - collapseStart))
        } else {
            collapse = easeInOut(1 - (phase - collapseEnd) / (1 - collapseEnd))
        }

        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        let inset: CGFloat = 3
        let drift = sin(phase * 2 * .pi) * 1.5

        for row in 0..<rows {
            for col in 0..<columns {
                // Pair columns together as collapse increases, simulating
                // adjacent weights merging into a shared quantized bucket.
                let pairedCol = col - (col % 2 == 1 ? 1 : 0)
                let effectiveCol = lerp(Double(col), Double(pairedCol), collapse)
                let pairedRow = row - (row % 2 == 1 ? 1 : 0)
                let effectiveRow = lerp(Double(row), Double(pairedRow), collapse)

                let x = CGFloat(effectiveCol) * cellWidth + inset + CGFloat(drift)
                let y = CGFloat(effectiveRow) * cellHeight + inset

                let shrink = lerp(1.0, 0.72, collapse)
                let w: CGFloat = (cellWidth - inset * 2) * CGFloat(shrink)
                let h: CGFloat = (cellHeight - inset * 2) * CGFloat(shrink)

                let rect = CGRect(x: x, y: y, width: w, height: h)
                let cornerRadius = min(w, h) * 0.28

                // Cells belonging to a merged pair brighten as they collapse,
                // representing higher information density per remaining block.
                let isMergedAnchor = (row % 2 == 0) && (col % 2 == 0)
                let baseOpacity = isMergedAnchor ? 0.55 : 0.28
                let mergedOpacity = isMergedAnchor ? 0.95 : 0.0
                let opacity = lerp(baseOpacity, mergedOpacity, collapse)

                let flicker = 0.06 * sin(phase * 2 * .pi * 3 + Double(row * columns + col))
                let finalOpacity = max(0, min(1, opacity + flicker * (1 - collapse)))

                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                graphicsContext.fill(path, with: .color(.white.opacity(finalOpacity)))

                if collapse > 0.05 && isMergedAnchor {
                    graphicsContext.stroke(
                        path,
                        with: .color(.white.opacity(collapse * 0.5)),
                        lineWidth: 0.75
                    )
                }
            }
        }
    }

    private func easeInOut(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return clamped < 0.5
            ? 2 * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 2) / 2
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
