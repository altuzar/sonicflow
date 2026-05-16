import SwiftUI

/// Touch-friendly horizontal volume slider with optional embedded level meter.
/// Drag anywhere on the track. Click-to-jump. Haptic ticks on every 5%.
struct FluidSlider: View {
    @Binding var value: Double          // 0...1
    var height: CGFloat = 24
    var accent: Color = .accentColor
    /// Live level meter (0...1). Drawn as a soft glow inside the filled region.
    var levelMeter: Double = 0

    @State private var lastHapticBucket: Int = -1
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Thumb is smaller than the track. The fill always extends UNDER
            // the thumb's right edge, so at 100% the blue fully covers the
            // track and the thumb fits cleanly inside.
            let thumbDiameter = max(14, height * 0.8)
            let travel = max(1, w - thumbDiameter)

            let clampedValue = max(0, min(1, value))
            let thumbLeft = clampedValue * travel
            // Fill spans from track-left under the thumb to the thumb's right
            // edge — at 100% this equals `w`, so the blue reaches the very
            // end of the track.
            let fill = thumbLeft + thumbDiameter
            let meter = max(0, min(1, levelMeter)) * fill

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fill)

                if meter > 1 {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: meter)
                        .blendMode(.plusLighter)
                        .animation(.easeOut(duration: 0.08), value: meter)
                }

                // Thumb sits at thumbLeft, fully inside the track at all values.
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                    .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 0.5))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: thumbLeft)
                    .scaleEffect(isDragging ? 1.08 : 1.0, anchor: .center)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isDragging)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        // Place thumb so its center tracks the cursor.
                        let cx = g.location.x - thumbDiameter / 2
                        let frac = max(0, min(1, cx / travel))
                        value = Double(frac)
                        emitHapticIfNeeded(for: frac)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: height)
    }

    private func emitHapticIfNeeded(for frac: Double) {
        let bucket = Int(frac * 20)        // every 5%
        guard bucket != lastHapticBucket else { return }
        lastHapticBucket = bucket
        HapticFeedback.tick()
    }
}
