import SwiftUI

struct SignalCanvasView: View {
    let points: [TrailPoint]
    let current: CGPoint
    let headingRadians: Double
    let showSurveyor: Bool
    let calibrationStart: CGPoint?
    let pendingReanchorPoint: CGPoint?
    /// Baseline uniform scale about the view center (smaller = more "zoomed out" for long walks).
    /// The user's pinch / zoom-button input multiplies on top of this.
    var contentScale: CGFloat = 1.0
    /// Which sample floor plan to draw under the trail/heatmap. `.blank` uses
    /// a plain shell with no rooms.
    var floorPlan: FloorPlanTemplate = .blank
    let onMapTap: ((CGPoint) -> Void)?

    @Environment(\.theme) private var theme

    @State private var userScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @GestureState private var dragDelta: CGSize = .zero
    @State private var selectedPointID: UUID?

    private let minUserScale: CGFloat = 0.4
    private let maxUserScale: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.4
    private let tapSlop: CGFloat = 6
    private let pointHitRadius: CGFloat = 18

    private var effectiveScale: CGFloat {
        contentScale * userScale * pinchDelta
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: panOffset.width + dragDelta.width,
            height: panOffset.height + dragDelta.height
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let scale = effectiveScale
            let offset = effectiveOffset
            let selectedPoint = selectedPointID.flatMap { id in points.first(where: { $0.id == id }) }

            ZStack(alignment: .topTrailing) {
                mapCanvas(size: geometry.size, scale: scale, offset: offset)

                gestureLayer(center: center)

                zoomControls
                    .padding(12)

                if let selectedPoint {
                    pointInfoBubble(
                        for: selectedPoint,
                        center: center,
                        scale: scale,
                        offset: offset,
                        canvasSize: geometry.size
                    )
                }
            }
        }
        .background(theme.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.canvasStroke, lineWidth: 1)
        )
    }

    // MARK: - Canvas

    private func mapCanvas(size canvasSize: CGSize, scale: CGFloat, offset: CGSize) -> some View {
        Canvas { context, size in
            let innerCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let mapRect = CGRect(origin: .zero, size: size).insetBy(dx: 22, dy: 22)

            context.concatenate(
                CGAffineTransform(translationX: innerCenter.x + offset.width, y: innerCenter.y + offset.height)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -innerCenter.x, y: -innerCenter.y)
            )

            drawFloorPlan(in: &context, rect: mapRect)
            drawHeatMap(in: &context, center: innerCenter)
            drawPath(in: &context, center: innerCenter)
            drawCalibration(in: &context, center: innerCenter)
            if showSurveyor {
                drawSurveyor(in: &context, center: innerCenter)
            }
        } symbols: {
            SurveyorSymbol()
                .tag(SurveyorSymbol.id)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    // MARK: - Gestures

    private func gestureLayer(center: CGPoint) -> some View {
        let drag = DragGesture(minimumDistance: 0)
            .updating($dragDelta) { value, state, _ in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > tapSlop {
                    state = value.translation
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance <= tapSlop {
                    handleTap(at: value.location, center: center)
                } else {
                    panOffset.width += value.translation.width
                    panOffset.height += value.translation.height
                }
            }

        let pinch = MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in
                state = value
            }
            .onEnded { value in
                userScale = clamp(userScale * value, minUserScale, maxUserScale)
            }

        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(SimultaneousGesture(drag, pinch))
    }

    private func handleTap(at screenLocation: CGPoint, center: CGPoint) {
        let scale = effectiveScale
        let offset = effectiveOffset
        let mapPoint = CGPoint(
            x: (screenLocation.x - center.x - offset.width) / scale,
            y: (screenLocation.y - center.y - offset.height) / scale
        )

        let hitRadiusInMapUnits = pointHitRadius / max(scale, 0.001)
        if let hit = nearestTrailPoint(to: mapPoint, withinRadius: hitRadiusInMapUnits) {
            selectedPointID = hit.id
            return
        }

        selectedPointID = nil
        onMapTap?(mapPoint)
    }

    private func nearestTrailPoint(to mapPoint: CGPoint, withinRadius radius: CGFloat) -> TrailPoint? {
        var best: (point: TrailPoint, distance: CGFloat)?
        for p in points {
            let d = hypot(p.position.x - mapPoint.x, p.position.y - mapPoint.y)
            if d <= radius, d < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (p, d)
            }
        }
        return best?.point
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        VStack(spacing: 8) {
            zoomButton(icon: "plus") { zoom(by: zoomStep) }
                .disabled(userScale >= maxUserScale - 0.001)
            zoomButton(icon: "minus") { zoom(by: 1.0 / zoomStep) }
                .disabled(userScale <= minUserScale + 0.001)
            zoomButton(icon: "scope") { recenter() }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func zoomButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.cardFill.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.cardStroke, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func zoom(by factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.18)) {
            userScale = clamp(userScale * factor, minUserScale, maxUserScale)
        }
    }

    private func recenter() {
        withAnimation(.easeOut(duration: 0.25)) {
            panOffset = .zero
            userScale = 1.0
            selectedPointID = nil
        }
    }

    // MARK: - Point info bubble

    private func pointInfoBubble(
        for point: TrailPoint,
        center: CGPoint,
        scale: CGFloat,
        offset: CGSize,
        canvasSize: CGSize
    ) -> some View {
        let screenX = point.position.x * scale + center.x + offset.width
        let screenY = point.position.y * scale + center.y + offset.height

        // Place the bubble above the point when there's room, below otherwise.
        let bubbleYOffset: CGFloat = screenY < 80 ? 60 : -60
        let clampedX = min(max(screenX, 100), canvasSize.width - 100)
        let clampedY = min(max(screenY + bubbleYOffset, 40), canvasSize.height - 40)

        return PointInfoCard(
            point: point,
            onDismiss: { selectedPointID = nil }
        )
        .position(x: clampedX, y: clampedY)
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Drawing

    private func drawFloorPlan(in context: inout GraphicsContext, rect: CGRect) {
        let shell = RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect)
        context.fill(shell, with: .color(Color(red: 0.28, green: 0.27, blue: 0.25)))

        let rooms = floorPlan.rooms
        guard !rooms.isEmpty else {
            // Blank template — leave the plain shell so the heatmap reads on a
            // clean surface. Outer outline adds visual weight without implying
            // any particular floor layout.
            context.stroke(shell, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
            return
        }

        for room in rooms {
            let roomRect = denormalizedRect(room.normalizedRect, in: rect)
            let roomPath = RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: roomRect)
            context.fill(roomPath, with: .color(room.tint.color.opacity(0.92)))
            context.stroke(roomPath, with: .color(Color.black.opacity(0.35)), lineWidth: 1)

            // Light-touch "furniture" hint — two subtle rectangles — so rooms
            // don't read as uniform blocks at a glance.
            let inset = roomRect.insetBy(dx: 10, dy: 10)
            if inset.width > 24, inset.height > 24 {
                var furniture = Path()
                furniture.addRect(CGRect(
                    x: inset.minX,
                    y: inset.minY,
                    width: inset.width * 0.5,
                    height: inset.height * 0.22
                ))
                furniture.addRect(CGRect(
                    x: inset.maxX - inset.width * 0.26,
                    y: inset.maxY - inset.height * 0.24,
                    width: inset.width * 0.22,
                    height: inset.height * 0.18
                ))
                context.stroke(furniture, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
            }

            // Only draw a label when the room is large enough that the text
            // won't overflow / clip.
            if roomRect.width >= 48, roomRect.height >= 28 {
                let label = Text(room.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                context.draw(
                    label,
                    at: CGPoint(x: roomRect.midX, y: roomRect.midY),
                    anchor: .center
                )
            }
        }
    }

    private func denormalizedRect(_ normalized: CGRect, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + normalized.minX * rect.width,
            y: rect.minY + normalized.minY * rect.height,
            width: normalized.width * rect.width,
            height: normalized.height * rect.height
        )
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
        guard !points.isEmpty else { return }

        if points.count > 1 {
            var path = Path()
            path.move(to: translated(points[0].position, center: center))
            for index in 1..<points.count {
                path.addLine(to: translated(points[index].position, center: center))
            }
            context.stroke(path, with: .color(Color.blue.opacity(0.95)), lineWidth: 4)
        }

        for point in points {
            let pt = translated(point.position, center: center)
            let isHighlighted = point.id == selectedPointID
            let radius: CGFloat = isHighlighted ? 8 : 5.5
            let waypoint = Path(ellipseIn: CGRect(
                x: pt.x - radius, y: pt.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.fill(
                waypoint,
                with: .color(isHighlighted ? Color.yellow : Color.blue)
            )
            context.stroke(
                waypoint,
                with: .color(.white.opacity(0.9)),
                lineWidth: isHighlighted ? 2.5 : 1.5
            )
        }

        if let id = selectedPointID, let point = points.first(where: { $0.id == id }) {
            let pt = translated(point.position, center: center)
            let ring = Path(ellipseIn: CGRect(x: pt.x - 16, y: pt.y - 16, width: 32, height: 32))
            context.stroke(ring, with: .color(Color.yellow.opacity(0.6)), lineWidth: 2)
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

    private func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T {
        min(max(x, lo), hi)
    }
}

private struct PointInfoCard: View {
    let point: TrailPoint
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        df.dateStyle = .none
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(point.quality.color)
                    .frame(width: 8, height: 8)
                Text(point.quality.description)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 14) {
                infoColumn(
                    caption: "Latency",
                    value: point.latencyMs.map { "\(Int($0)) ms" } ?? "—"
                )
                infoColumn(
                    caption: "Captured",
                    value: Self.timeFormatter.string(from: point.timestamp)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .fixedSize()
    }

    private func infoColumn(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
        }
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
