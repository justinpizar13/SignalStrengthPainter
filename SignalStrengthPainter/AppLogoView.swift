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
        }
        .frame(width: size, height: size)
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
