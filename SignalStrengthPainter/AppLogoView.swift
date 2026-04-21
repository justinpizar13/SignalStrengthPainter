import SwiftUI

/// Wi-Fi Buddy branded logo.
///
/// Renders a classic "signal-strength" Wi-Fi glyph — three concentric arcs and
/// a center dot — in a traffic-light palette (green → yellow → orange → red).
/// The arcs are evenly spaced so the wave pattern reads cleanly at any size,
/// and the full glyph is vertically centered so there is equal breathing room
/// above the outer arc and below the dot.
///
/// The in-app logo renders on a **transparent** background so it composites
/// cleanly over themed cards and headers. The home-screen app icon
/// (`AppIcon.appiconset/icon_1024x1024.png`) uses the same glyph on a dark
/// gray squircle; the geometry in this file and in
/// `scripts/generate_app_icon.py` are kept in lockstep so both marks read
/// identically.
///
/// Sized via the `size` parameter; every element scales proportionally so the
/// logo holds up from 26pt (survey headers) to 100pt (paywall hero).
struct AppLogoView: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { context, canvasSize in
            drawWifiGlyph(context: context, size: canvasSize)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Geometry

    // Geometry shared with `scripts/generate_app_icon.py` so the in-app
    // logo matches the home-screen icon PNG pixel-for-pixel (at any scale).
    //
    // Vertical placement: the glyph spans from `cy - outerR` at the top to
    // `cy + dotR` at the bottom. With `outerR = 0.445`, `dotR = 0.055` and
    // `cy = 0.695`, the bounding box is y ∈ [0.250, 0.750] — i.e. perfectly
    // centered in the square canvas.
    //
    // Radial spacing: stroke width is 0.080 and each successive arc is
    // inset by stroke + 0.050 from the previous, giving a consistent 0.050
    // gap between neighboring strokes and between the inner arc and the
    // dot. That even cadence is what makes the signal-wave pattern read.
    static let glyphCYFrac: CGFloat = 0.695
    static let strokeWFrac: CGFloat = 0.080
    static let dotRFrac: CGFloat = 0.055
    static let arcFracs: [CGFloat] = [0.445, 0.315, 0.185]

    // Traffic-light palette used for the glyph. Outer arc is green, middle
    // is yellow, inner is orange, and the center dot is red — a classic
    // Wi-Fi "signal strength" cue. Colors are shared with
    // `scripts/generate_app_icon.py`.
    static let outerArcColor = Color(red: 0.30, green: 0.85, blue: 0.40)
    static let middleArcColor = Color(red: 0.98, green: 0.82, blue: 0.22)
    static let innerArcColor = Color(red: 0.98, green: 0.52, blue: 0.22)
    static let dotColor = Color(red: 0.98, green: 0.32, blue: 0.32)

    // MARK: - Drawing

    private func drawWifiGlyph(context: GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height * Self.glyphCYFrac
        let strokeW = size.width * Self.strokeWFrac

        let arcColors = [Self.outerArcColor, Self.middleArcColor, Self.innerArcColor]
        for (rFrac, color) in zip(Self.arcFracs, arcColors) {
            let rOuter = size.width * rFrac
            let rCenter = rOuter - strokeW / 2

            var path = Path()
            path.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: rCenter,
                startAngle: .degrees(225),
                endAngle: .degrees(315),
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
            )
        }

        let dotR = size.width * Self.dotRFrac
        let dotRect = CGRect(
            x: cx - dotR,
            y: cy - dotR,
            width: dotR * 2,
            height: dotR * 2
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(Self.dotColor))
    }
}

#Preview("Dark") {
    VStack(spacing: 24) {
        AppLogoView(size: 120)
        AppLogoView(size: 80)
        AppLogoView(size: 44)
        AppLogoView(size: 28)
    }
    .padding()
    .background(Color(white: 0.12))
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    VStack(spacing: 24) {
        AppLogoView(size: 120)
        AppLogoView(size: 80)
        AppLogoView(size: 44)
        AppLogoView(size: 28)
    }
    .padding()
    .background(Color.white)
    .preferredColorScheme(.light)
}
