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
        .background(Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea())
        .foregroundStyle(.white)
        .onDisappear {
            viewModel.stopTracking()
        }
    }

    // MARK: - Calibration Layout

    private var calibrationLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                mapCanvas(contentScale: viewModel.mapContentScale)
                    .frame(height: 320)
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                instructionCard
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                scaleLegend
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                controlButtons
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                if viewModel.showsRotationControl {
                    rotationCalibration
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                }

                footer
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Expanded Survey Layout

    private var expandedSurveyLayout: some View {
        VStack(spacing: 0) {
            compactSurveyHeader
                .padding(.top, 8)
                .padding(.horizontal, 16)

            mapCanvas(contentScale: viewModel.mapContentScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .padding(.top, 10)
                .padding(.horizontal, 12)

            compactInstructionStrip
                .padding(.top, 10)
                .padding(.horizontal, 16)

            compactScaleLegend
                .padding(.top, 8)
                .padding(.horizontal, 16)

            controlButtons
                .padding(.top, 12)
                .padding(.horizontal, 16)

            if viewModel.showsRotationControl {
                rotationCalibration
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }

            compactFooter
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Walk The Space")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Use AR anchoring to track movement on the floor plan, then paint signal quality directly onto the map.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            trackingStatusBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactSurveyHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "map.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Walk The Space")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            trackingStatusPill
        }
    }

    private var trackingStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.trackingIsReliable ? Color(red: 0.25, green: 0.86, blue: 0.43) : Color(red: 0.98, green: 0.78, blue: 0.28))
                .frame(width: 8, height: 8)
            Text(viewModel.trackingStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
    }

    private var trackingStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.trackingIsReliable ? Color(red: 0.25, green: 0.86, blue: 0.43) : Color(red: 0.98, green: 0.78, blue: 0.28))
                .frame(width: 6, height: 6)
            Text(viewModel.trackingStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.instructionTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(viewModel.instructionDetail)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var compactInstructionStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.instructionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(viewModel.instructionDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Scale Legend

    private var scaleLegend: some View {
        VStack(spacing: 8) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.39, blue: 0.34),
                    Color(red: 0.98, green: 0.78, blue: 0.28),
                    Color(red: 0.25, green: 0.86, blue: 0.43),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())

            HStack {
                Text("Weaker / higher latency")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("Stronger / lower latency")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var compactScaleLegend: some View {
        HStack(spacing: 10) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.39, blue: 0.34),
                    Color(red: 0.98, green: 0.78, blue: 0.28),
                    Color(red: 0.25, green: 0.86, blue: 0.43),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 6)
            .clipShape(Capsule())

            Text("Weak → Strong")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.performPrimaryAction()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: primaryActionIcon)
                    Text(viewModel.primaryActionTitle)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(!viewModel.canRunPrimaryAction)
            .opacity(viewModel.canRunPrimaryAction ? 1 : 0.45)

            HStack(spacing: 10) {
                if viewModel.isTracking {
                    Button {
                        viewModel.stopSurvey()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                            Text("Stop")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.98, green: 0.55, blue: 0.22).opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 0.98, green: 0.55, blue: 0.22).opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                }

                Button {
                    showResetConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("Reset")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }

                Button {
                    viewModel.reanchorCurrentLocation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 12))
                        Text("Re-anchor")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(viewModel.isTracking ? .white.opacity(0.7) : .white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .disabled(!viewModel.isTracking)
            }
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

    private var primaryActionIcon: String {
        switch viewModel.calibrationStage {
        case .idle: return "play.fill"
        case .readyToStart: return "figure.walk"
        default: return "location.fill"
        }
    }

    // MARK: - Rotation Calibration

    private var rotationCalibration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Map Rotation")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("\(Int(viewModel.mapRotationDegrees))°")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
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

            Text("Adjust if the AR path direction doesn't match your floor plan orientation.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            footerMetric(
                icon: "bolt.fill",
                label: "Latency",
                value: viewModel.latestLatencyMs.map { "\(Int($0)) ms" } ?? "—"
            )
            footerMetric(
                icon: "mappin.and.ellipse",
                label: "Points",
                value: "\(viewModel.trail.count)"
            )
        }
    }

    private var compactFooter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                if let ms = viewModel.latestLatencyMs {
                    Text("\(Int(ms)) ms")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text("— ms")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("\(viewModel.trail.count) pts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func footerMetric(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
