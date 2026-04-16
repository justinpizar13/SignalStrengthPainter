import SwiftUI

struct SignalCanvasView: View {
    let points: [TrailPoint]
    let current: CGPoint
    let headingRadians: Double
    let showSurveyor: Bool
    let calibrationStart: CGPoint?
    let pendingReanchorPoint: CGPoint?
    /// Uniform scale about the view center (smaller = more "zoomed out" for long walks).
    var contentScale: CGFloat = 1.0
    let onMapTap: ((CGPoint) -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let mapRect = CGRect(origin: .zero, size: size).insetBy(dx: 22, dy: 22)

                if contentScale != 1, contentScale > 0.001 {
                    context.concatenate(
                        CGAffineTransform(translationX: center.x, y: center.y)
                            .scaledBy(x: contentScale, y: contentScale)
                            .translatedBy(x: -center.x, y: -center.y)
                    )
                }

                drawFloorPlan(in: &context, rect: mapRect)
                drawHeatMap(in: &context, center: center)
                drawPath(in: &context, center: center)
                drawCalibration(in: &context, center: center)
                if showSurveyor {
                    drawSurveyor(in: &context, center: center)
                }
            } symbols: {
                SurveyorSymbol()
                    .tag(SurveyorSymbol.id)
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard let onMapTap else { return }
                                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                let scale = contentScale > 0.001 ? contentScale : 1.0
                                let translated = CGPoint(
                                    x: (value.location.x - center.x) / scale,
                                    y: (value.location.y - center.y) / scale
                                )
                                onMapTap(translated)
                            }
                    )
            }
        }
        .background(theme.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.canvasStroke, lineWidth: 1)
        )
    }

    private func drawFloorPlan(in context: inout GraphicsContext, rect: CGRect) {
        let shell = RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect)
        context.fill(shell, with: .color(Color(red: 0.28, green: 0.27, blue: 0.25)))

        let rooms: [(CGRect, Color)] = [
            (CGRect(x: rect.minX + 16, y: rect.midY + 12, width: rect.width * 0.32, height: rect.height * 0.28), Color(red: 0.56, green: 0.42, blue: 0.25)),
            (CGRect(x: rect.minX + 24, y: rect.minY + 28, width: rect.width * 0.34, height: rect.height * 0.22), Color(red: 0.47, green: 0.43, blue: 0.35)),
            (CGRect(x: rect.midX - 40, y: rect.minY + 24, width: rect.width * 0.22, height: rect.height * 0.27), Color(red: 0.42, green: 0.39, blue: 0.28)),
            (CGRect(x: rect.midX + 10, y: rect.midY - 14, width: rect.width * 0.28, height: rect.height * 0.3), Color(red: 0.4, green: 0.45, blue: 0.31)),
            (CGRect(x: rect.midX + 26, y: rect.minY + 26, width: rect.width * 0.24, height: rect.height * 0.23), Color(red: 0.38, green: 0.41, blue: 0.33))
        ]

        for (roomRect, color) in rooms {
            let room = RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: roomRect)
            context.fill(room, with: .color(color.opacity(0.92)))
            context.stroke(room, with: .color(Color.black.opacity(0.35)), lineWidth: 1)

            let inset = roomRect.insetBy(dx: 10, dy: 10)
            var furniture = Path()
            furniture.addRect(CGRect(x: inset.minX, y: inset.minY, width: inset.width * 0.5, height: inset.height * 0.22))
            furniture.addRect(CGRect(x: inset.maxX - inset.width * 0.26, y: inset.maxY - inset.height * 0.24, width: inset.width * 0.22, height: inset.height * 0.18))
            context.stroke(furniture, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
        }

        var corridor = Path()
        corridor.move(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + 20))
        corridor.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.maxY - 18))
        corridor.move(to: CGPoint(x: rect.minX + 18, y: rect.midY))
        corridor.addLine(to: CGPoint(x: rect.maxX - 18, y: rect.midY))
        context.stroke(corridor, with: .color(Color.white.opacity(0.16)), lineWidth: 8)
    }

    private func drawHeatMap(in context: inout GraphicsContext, center: CGPoint) {
        for point in points {
            let translatedPoint = translated(point.position, center: center)
            let glowRect = CGRect(x: translatedPoint.x - 54, y: translatedPoint.y - 54, width: 108, height: 108)
            let gradient = Gradient(stops: [
                .init(color: point.heatColor.opacity(0.82), location: 0),
                .init(color: point.heatColor.opacity(0.45), location: 0.45),
                .init(color: point.heatColor.opacity(0.08), location: 1)
            ])

            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    gradient,
                    center: translatedPoint,
                    startRadius: 4,
                    endRadius: 54
                )
            )
        }
    }

    private func drawPath(in context: inout GraphicsContext, center: CGPoint) {
        guard points.count > 1 else { return }

        for index in 1..<points.count {
            let previous = translated(points[index - 1].position, center: center)
            let next = translated(points[index].position, center: center)
            var path = Path()
            path.move(to: previous)
            path.addLine(to: next)
            context.stroke(path, with: .color(Color.blue.opacity(0.95)), lineWidth: 4)

            let waypoint = Path(ellipseIn: CGRect(x: next.x - 5.5, y: next.y - 5.5, width: 11, height: 11))
            context.fill(waypoint, with: .color(Color.blue))
            context.stroke(waypoint, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }
    }

    private func drawCalibration(in context: inout GraphicsContext, center: CGPoint) {
        if let start = calibrationStart {
            let translatedStart = translated(start, center: center)
            let startMarker = Path(ellipseIn: CGRect(x: translatedStart.x - 9, y: translatedStart.y - 9, width: 18, height: 18))
            context.fill(startMarker, with: .color(Color.orange))
            context.stroke(startMarker, with: .color(.white.opacity(0.9)), lineWidth: 2)
        }

        if let reanchorPoint = pendingReanchorPoint {
            let translatedPoint = translated(reanchorPoint, center: center)
            let reanchorMarker = Path(ellipseIn: CGRect(x: translatedPoint.x - 8, y: translatedPoint.y - 8, width: 16, height: 16))
            context.fill(reanchorMarker, with: .color(Color.purple.opacity(0.9)))
            context.stroke(reanchorMarker, with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
    }

    private func drawSurveyor(in context: inout GraphicsContext, center: CGPoint) {
        let currentPoint = translated(current, center: center)
        let pulseRect = CGRect(x: currentPoint.x - 20, y: currentPoint.y - 20, width: 40, height: 40)
        context.fill(
            Path(ellipseIn: pulseRect),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.32), .clear]),
                center: currentPoint,
                startRadius: 1,
                endRadius: 20
            )
        )

        if let symbol = context.resolveSymbol(id: SurveyorSymbol.id) {
            context.draw(symbol, at: currentPoint)
        }

        let directionLength: CGFloat = 26
        let facingPoint = CGPoint(
            x: currentPoint.x + CGFloat(cos(headingRadians)) * directionLength,
            y: currentPoint.y + CGFloat(sin(headingRadians)) * directionLength
        )
        var direction = Path()
        direction.move(to: currentPoint)
        direction.addLine(to: facingPoint)
        context.stroke(direction, with: .color(Color.white.opacity(0.75)), lineWidth: 2)
    }

    private func translated(_ point: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + point.x, y: center.y + point.y)
    }
}

private struct SurveyorSymbol: View {
    static let id = "surveyor"

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)

            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 23))
                .foregroundStyle(Color(red: 0.11, green: 0.5, blue: 0.99), Color(red: 1.0, green: 0.78, blue: 0.28))
                .background(Circle().fill(Color.white))
        }
    }
}
