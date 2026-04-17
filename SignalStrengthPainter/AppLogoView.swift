import SwiftUI

/// Wi-Fi Buddy branded logo.
///
/// Renders the Wi-Fi glyph on a **transparent** background in a subtle
/// iridescent "Apple glass" material: a predominantly silvery-white base with
/// very muted pastel hints of pink / lavender / mint / peach, plus a gentle
/// diagonal white sheen for glassiness. Three small 4-pointed sparkles sit in
/// the upper-right. Sized via the `size` parameter; every element scales
/// proportionally so the logo reads well from 26pt up to 100pt+.
///
/// The home-screen app icon (`AppIcon.appiconset/icon_1024x1024.png`) uses
/// the same iridescent material on a solid black squircle. In-app this view
/// is drawn transparently so it composites cleanly over themed cards and
/// headers.
struct AppLogoView: View {
    var size: CGFloat = 60

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let palette = IridescentPalette.resolved(for: colorScheme)
            drawWifiGlyph(context: context, size: canvasSize, palette: palette)
            drawSheen(context: context, size: canvasSize, palette: palette)
            drawSparkles(context: context, size: canvasSize, palette: palette)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Layers

    // Geometry shared with `scripts/generate_app_icon.py` so the in-app
    // logo matches the home-screen icon PNG pixel-for-pixel (at any scale).
    private static let glyphCYFrac: CGFloat = 0.635
    private static let arcFracs: [(CGFloat, CGFloat)] = [
        (0.425, 0.096),
        (0.302, 0.096),
        (0.180, 0.096),
    ]
    private static let dotRFrac: CGFloat = 0.064

    private func drawWifiGlyph(context: GraphicsContext, size: CGSize, palette: IridescentPalette) {
        let cx = size.width / 2
        let cy = size.height * Self.glyphCYFrac

        let shading = iridescentShading(size: size, palette: palette)

        for (rFrac, wFrac) in Self.arcFracs {
            let rOuter = size.width * rFrac
            let lineW = size.width * wFrac
            let rCenter = rOuter - lineW / 2

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
                with: shading,
                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
            )
        }

        let dotR = size.width * Self.dotRFrac
        let dotRect = CGRect(
            x: cx - dotR,
            y: cy - dotR,
            width: dotR * 2,
            height: dotR * 2
        )
        context.fill(Path(ellipseIn: dotRect), with: shading)
    }

    private func drawSheen(context: GraphicsContext, size: CGSize, palette: IridescentPalette) {
        // A tight diagonal specular band concentrated over the upper-left of
        // the glyph, clipped to the Wi-Fi glyph so the highlight reads as
        // polished glass rather than a full-canvas wash.
        let cx = size.width / 2
        let cy = size.height * Self.glyphCYFrac

        var glyphPath = Path()
        for (rFrac, wFrac) in Self.arcFracs {
            let rOuter = size.width * rFrac
            let lineW = size.width * wFrac
            let rCenter = rOuter - lineW / 2
            var arcPath = Path()
            arcPath.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: rCenter,
                startAngle: .degrees(225),
                endAngle: .degrees(315),
                clockwise: false
            )
            glyphPath.addPath(
                arcPath.strokedPath(
                    StrokeStyle(lineWidth: lineW, lineCap: .round)
                )
            )
        }
        let dotR = size.width * Self.dotRFrac
        glyphPath.addEllipse(
            in: CGRect(
                x: cx - dotR,
                y: cy - dotR,
                width: dotR * 2,
                height: dotR * 2
            )
        )

        // Clip to the glyph, then fill a tight diagonal specular band across
        // the upper-left of the canvas. The gradient runs TL → BR so its
        // iso-lines are parallel to u+v=const — matching the PNG sheen
        // geometry (peak at u+v ≈ 0.78, i.e. gradient location ≈ 0.39).
        var clipped = context
        clipped.clip(to: glyphPath)

        let sheenColor = palette.sheenColor
        let sheen: GraphicsContext.Shading = .linearGradient(
            Gradient(stops: [
                .init(color: sheenColor.opacity(0.0), location: 0.00),
                .init(color: sheenColor.opacity(0.0), location: 0.26),
                .init(color: sheenColor.opacity(palette.sheenAlpha), location: 0.39),
                .init(color: sheenColor.opacity(0.0), location: 0.52),
                .init(color: sheenColor.opacity(0.0), location: 1.00),
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: size.height)
        )
        clipped.fill(Path(CGRect(origin: .zero, size: size)), with: sheen)
    }

    private func drawSparkles(context: GraphicsContext, size: CGSize, palette: IridescentPalette) {
        // (x fraction, y fraction, arm-length fraction)
        let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
            (0.810, 0.185, 0.082),
            (0.905, 0.295, 0.050),
            (0.705, 0.095, 0.042),
        ]

        let shading = iridescentShading(size: size, palette: palette, dim: 0.9)

        for (xFrac, yFrac, armFrac) in sparkles {
            let center = CGPoint(x: size.width * xFrac, y: size.height * yFrac)
            let armLength = size.width * armFrac
            let waist = armLength * 0.28

            var star = Path()
            let arms = 4
            for i in 0..<(arms * 2) {
                let angle = Angle.degrees(Double(i) * 45 - 90)
                let r = i.isMultiple(of: 2) ? armLength : waist
                let pt = CGPoint(
                    x: center.x + CGFloat(cos(angle.radians)) * r,
                    y: center.y + CGFloat(sin(angle.radians)) * r
                )
                if i == 0 {
                    star.move(to: pt)
                } else {
                    star.addLine(to: pt)
                }
            }
            star.closeSubpath()
            context.fill(star, with: shading)
        }
    }

    // MARK: - Iridescent shader

    /// A diagonal iridescent gradient running from the upper-left toward the
    /// lower-right of the canvas. Pastel stops stay very close to the palette
    /// base color so the overall read is a shimmery material, not a rainbow.
    /// The `dim` parameter slightly attenuates saturation (used for sparkles).
    private func iridescentShading(
        size: CGSize,
        palette: IridescentPalette,
        dim: CGFloat = 1.0
    ) -> GraphicsContext.Shading {
        let stops: [Gradient.Stop] = palette.gradientStops(dim: dim)
        return .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: size.height)
        )
    }
}

// MARK: - Palette

/// Color palette for the iridescent Wi-Fi glyph. The `light` variant swaps in
/// darker pastel tones so the glyph retains contrast against white card
/// backgrounds; the `dark` variant uses the silvery-white "Apple glass" tones
/// that match the home-screen app icon.
struct IridescentPalette {
    let pink: Color
    let silverWarm: Color
    let peach: Color
    let mint: Color
    let lavender: Color
    let silverCool: Color

    /// Color used for the diagonal specular highlight. White on the dark
    /// palette reads as a bright glass sheen; a slightly warm off-white on
    /// the light palette lifts the darker glyph without washing it out.
    let sheenColor: Color
    let sheenAlpha: Double

    func gradientStops(dim: CGFloat) -> [Gradient.Stop] {
        func d(_ c: Color) -> Color { c.dimmed(by: dim) }
        return [
            .init(color: d(pink),        location: 0.00),
            .init(color: d(silverWarm),  location: 0.20),
            .init(color: d(peach),       location: 0.40),
            .init(color: d(mint),        location: 0.60),
            .init(color: d(lavender),    location: 0.80),
            .init(color: d(silverCool),  location: 1.00),
        ]
    }

    static func resolved(for colorScheme: ColorScheme) -> IridescentPalette {
        colorScheme == .light ? .light : .dark
    }

    /// Silvery-white palette matching the app icon. Designed to read well on
    /// the dark theme's card surfaces (`cardFill = white @ 4% alpha` over a
    /// near-black background). Saturation is bumped slightly above a pure
    /// silver so the pink / mint / lavender / peach rainbow reads subtly
    /// through the glass sheen — matching the iridescent corners used in
    /// `scripts/generate_app_icon.py`.
    static let dark = IridescentPalette(
        pink:        Color(red: 1.00, green: 0.72, blue: 0.84),
        silverWarm:  Color(red: 0.94, green: 0.91, blue: 0.93),
        peach:       Color(red: 1.00, green: 0.83, blue: 0.65),
        mint:        Color(red: 0.74, green: 0.93, blue: 0.88),
        lavender:    Color(red: 0.80, green: 0.73, blue: 0.98),
        silverCool:  Color(red: 0.90, green: 0.91, blue: 0.93),
        sheenColor:  .white,
        sheenAlpha:  0.70
    )

    /// Darker slate palette for light mode. Preserves the same hue rotation
    /// (pink → silver → peach → mint → lavender → silver) but at a lower
    /// luminance so the glyph stays visible on white card fills. Slightly
    /// more saturated than a pure slate so the rainbow still reads subtly
    /// on a white background.
    static let light = IridescentPalette(
        pink:        Color(red: 0.48, green: 0.22, blue: 0.34),
        silverWarm:  Color(red: 0.27, green: 0.25, blue: 0.28),
        peach:       Color(red: 0.45, green: 0.32, blue: 0.20),
        mint:        Color(red: 0.20, green: 0.36, blue: 0.30),
        lavender:    Color(red: 0.28, green: 0.23, blue: 0.46),
        silverCool:  Color(red: 0.25, green: 0.26, blue: 0.28),
        // A soft warm off-white sheen at reduced intensity keeps the glass
        // highlight legible without blowing out the darker base.
        sheenColor:  Color(red: 1.0, green: 0.98, blue: 0.96),
        sheenAlpha:  0.40
    )
}

private extension Color {
    /// Scales the RGB components by `dim` without altering hue or alpha.
    /// Values are clamped to `[0, 1]`. `dim == 1` returns the color unchanged.
    func dimmed(by dim: CGFloat) -> Color {
        guard dim < 0.9999 else { return self }
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp: (CGFloat) -> Double = { Double(max(0, min(1, $0 * dim))) }
        return Color(red: clamp(r), green: clamp(g), blue: clamp(b), opacity: Double(a))
        #else
        return self
        #endif
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
