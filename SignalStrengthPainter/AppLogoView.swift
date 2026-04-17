import SwiftUI

struct AppLogoView: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height * 0.55

            let arcs: [(CGFloat, Color)] = [
                (0.42, Color(red: 76/255, green: 217/255, blue: 100/255)),
                (0.30, Color(red: 1.0, green: 204/255, blue: 0)),
                (0.18, Color(red: 1.0, green: 149/255, blue: 0)),
            ]

            let lineW = canvasSize.width * 0.07

            for (radiusFraction, color) in arcs {
                let r = canvasSize.width * radiusFraction
                var path = Path()
                path.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: .degrees(225),
                    endAngle: .degrees(315),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineW, lineCap: .round))
            }

            let dotR = canvasSize.width * 0.055
            let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(Color(red: 1.0, green: 59/255, blue: 48/255)))

            drawSparkles(context: context, size: canvasSize)
        }
        .frame(width: size, height: size)
    }

    private func drawSparkles(context: GraphicsContext, size: CGSize) {
        let sparkleColor = Color.white

        let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
            (0.78, 0.18, 0.09),
            (0.88, 0.30, 0.055),
            (0.68, 0.08, 0.045),
        ]

        for (xFrac, yFrac, rFrac) in sparkles {
            let center = CGPoint(x: size.width * xFrac, y: size.height * yFrac)
            let armLength = size.width * rFrac

            var star = Path()
            let arms = 4
            for i in 0..<(arms * 2) {
                let angle = Angle.degrees(Double(i) * 45 - 90)
                let isArm = i % 2 == 0
                let r = isArm ? armLength : armLength * 0.3
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

            context.fill(star, with: .color(sparkleColor.opacity(0.9)))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AppLogoView(size: 80)
        AppLogoView(size: 44)
        AppLogoView(size: 28)
    }
    .padding()
    .background(Color(white: 0.1))
}
