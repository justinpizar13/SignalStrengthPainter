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

    private func drawWifiGlyph(context: GraphicsContext, size: CGSize, palette: IridescentPalette) {
        let cx = size.width / 2
        let cy = size.height * 0.575

        // (outer bbox radius fraction, thickness fraction)
        let arcs: [(CGFloat, CGFloat)] = [
            (0.355, 0.080),
            (0.255, 0.080),
            (0.155, 0.080),
        ]

        let shading = iridescentShading(size: size, palette: palette)

        for (rFrac, wFrac) in arcs {
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

        let dotR = size.width * 0.055
        let dotRect = CGRect(
            x: cx - dotR,
            y: cy - dotR,
            width: dotR * 2,
            height: dotR * 2
        )
        context.fill(Path(ellipseIn: dotRect), with: shading)
    }

    private func drawSheen(context: GraphicsContext, size: CGSize, palette: IridescentPalette) {
        // A soft diagonal white band concentrated over the upper-left of the
        // glyph, masked to the Wi-Fi glyph shapes so it reads as glass
        // specular rather than a full-canvas wash.
        let cx = size.width / 2
        let cy = size.height * 0.575

        let arcs: [(CGFloat, CGFloat)] = [
            (0.355, 0.080),
            (0.255, 0.080),
            (0.155, 0.080),
        ]

        var glyphPath = Path()
        for (rFrac, wFrac) in arcs {
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
        let dotR = size.width * 0.055
        glyphPath.addEllipse(
            in: CGRect(
                x: cx - dotR,
                y: cy - dotR,
                width: dotR * 2,
                height: dotR * 2
            )
        )

        // Clip to the glyph, then fill a diagonal white band gradient across
        // the whole canvas. Only the glyph-intersecting portion renders.
        var clipped = context
        clipped.clip(to: glyphPath)

        let sheenColor = palette.sheenColor
        let sheen: GraphicsContext.Shading = .linearGradient(
            Gradient(stops: [
                .init(color: sheenColor.opacity(0.0), location: 0.0),
                .init(color: sheenColor.opacity(0.0), location: 0.30),
                .init(color: sheenColor.opacity(palette.sheenAlpha), location: 0.50),
                .init(color: sheenColor.opacity(0.0), location: 0.70),
                .init(color: sheenColor.opacity(0.0), location: 1.0),
            ]),
            startPoint: CGPoint(x: size.width, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
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
    /// near-black background).
    static let dark = IridescentPalette(
        pink:        Color(red: 0.972, green: 0.831, blue: 0.894),
        silverWarm:  Color(red: 0.929, green: 0.918, blue: 0.941),
        peach:       Color(red: 0.972, green: 0.953, blue: 0.906),
        mint:        Color(red: 0.906, green: 0.941, blue: 0.914),
        lavender:    Color(red: 0.906, green: 0.890, blue: 0.965),
        silverCool:  Color(red: 0.929, green: 0.933, blue: 0.937),
        sheenColor:  .white,
        sheenAlpha:  0.55
    )

    /// Darker slate palette for light mode. Preserves the same hue rotation
    /// (pink → silver → peach → mint → lavender → silver) but at a lower
    /// luminance so the glyph stays visible on white card fills.
    static let light = IridescentPalette(
        pink:        Color(red: 0.345, green: 0.200, blue: 0.275),
        silverWarm:  Color(red: 0.235, green: 0.230, blue: 0.255),
        peach:       Color(red: 0.330, green: 0.280, blue: 0.215),
        mint:        Color(red: 0.210, green: 0.275, blue: 0.230),
        lavender:    Color(red: 0.225, green: 0.210, blue: 0.330),
        silverCool:  Color(red: 0.230, green: 0.235, blue: 0.250),
        // A soft warm off-white sheen at reduced intensity keeps the glass
        // highlight legible without blowing out the darker base.
        sheenColor:  Color(red: 1.0, green: 0.98, blue: 0.96),
        sheenAlpha:  0.35
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
