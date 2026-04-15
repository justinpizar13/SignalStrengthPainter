import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SignalMapViewModel()
    @State private var showResetConfirmation = false

    var body: some View {
        Group {
            if viewModel.usesExpandedMapLayout {
                expandedSurveyLayout
            } else {
                calibrationLayout
            }
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea())
        .foregroundStyle(.white)
        .onDisappear {
            viewModel.stopTracking()
        }
    }

    private var calibrationLayout: some View {
        VStack(spacing: 18) {
            header

            mapCanvas(contentScale: viewModel.mapContentScale)
                .frame(maxHeight: .infinity)

            instructionCard
            scaleLegend

            controlButtons
            if viewModel.showsRotationControl {
                rotationCalibration
            }
            footer
        }
        .padding()
    }

    /// Map uses most of the screen; controls stay in a thin strip at the bottom.
    private var expandedSurveyLayout: some View {
        VStack(spacing: 8) {
            compactSurveyHeader

            mapCanvas(contentScale: viewModel.mapContentScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            compactInstructionStrip

            compactScaleLegend

            controlButtons

            if viewModel.showsRotationControl {
                rotationCalibration
            }

            compactFooter
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func mapCanvas(contentScale: CGFloat) -> some View {
        SignalCanvasView(
            points: viewModel.trail,
            current: viewModel.currentPosition,
            headingRadians: viewModel.headingRadians,
            showSurveyor: viewModel.isTracking,
            calibrationStart: viewModel.calibrationStartPoint,
            pendingReanchorPoint: viewModel.pendingReanchorPoint,
            contentScale: contentScale,
            onMapTap: { point in
                viewModel.handleMapTap(point)
            }
        )
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button(viewModel.primaryActionTitle) {
                viewModel.performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!viewModel.canRunPrimaryAction)

            if viewModel.isTracking {
                Button("Stop Survey") {
                    viewModel.stopSurvey()
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Button("Reset") {
                showResetConfirmation = true
            }
            .buttonStyle(.bordered)

            Button("Re-anchor Here") {
                viewModel.reanchorCurrentLocation()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isTracking)
        }
        .confirmationDialog(
            "Reset survey?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear map and all samples", role: .destructive) {
                viewModel.resetMap()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. You will lose the current path and measurements.")
        }
    }

    private var compactSurveyHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Walk The Space")
                .font(.headline.weight(.semibold))

            Spacer(minLength: 0)

            Circle()
                .fill(viewModel.trackingIsReliable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(viewModel.trackingStatus)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var compactInstructionStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.instructionTitle)
                .font(.subheadline.weight(.semibold))
            Text(viewModel.instructionDetail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var compactScaleLegend: some View {
        HStack(spacing: 8) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.39, blue: 0.34),
                    Color(red: 0.98, green: 0.78, blue: 0.28),
                    Color(red: 0.25, green: 0.86, blue: 0.43)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Weaker → Stronger")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var compactFooter: some View {
        HStack {
            if let ms = viewModel.latestLatencyMs {
                Text("\(Int(ms)) ms")
                    .font(.subheadline.weight(.medium))
            } else {
                Text("— ms")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text("\(viewModel.trail.count) pts")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Walk The Space")
                .font(.title2.bold())

            Text("Use AR anchoring to track movement on the floor plan, then paint signal quality directly onto the map as new samples arrive.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.trackingIsReliable ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                Text(viewModel.trackingStatus)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.instructionTitle)
                .font(.headline)

            Text(viewModel.instructionDetail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var scaleLegend: some View {
        VStack(spacing: 10) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.39, blue: 0.34),
                    Color(red: 0.98, green: 0.78, blue: 0.28),
                    Color(red: 0.25, green: 0.86, blue: 0.43)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            HStack {
                Text("Weaker / higher latency")
                Spacer()
                Text("Stronger / lower latency")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var rotationCalibration: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Map rotation")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(viewModel.mapRotationDegrees))°")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Slider(
                value: Binding(
                    get: { viewModel.mapRotationDegrees },
                    set: { viewModel.mapRotationDegrees = $0 }
                ),
                in: -180...180,
                step: 1
            )
                .tint(.blue)

            Text("Rotate the movement alignment without shifting the current marker if the AR path direction does not match the map orientation.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Latest sample")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                if let ms = viewModel.latestLatencyMs {
                    Text("\(Int(ms)) ms")
                        .font(.headline)
                } else {
                    Text("Timeout")
                        .font(.headline)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Points collected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                Text("\(viewModel.trail.count)")
                    .font(.headline)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
