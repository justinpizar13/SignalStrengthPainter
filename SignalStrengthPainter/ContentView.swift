import SwiftUI

struct ContentView: View {
    @Environment(\.theme) private var theme
    @StateObject private var viewModel = SignalMapViewModel()
    @State private var showResetConfirmation = false
    @State private var showRoomNameEditor = false
    /// Persisted across launches so the user's last picked floor plan is
    /// remembered. Default is `.blank` (the plain background).
    @AppStorage("floorPlanTemplate") private var floorPlanRawValue: String = FloorPlanTemplate.blank.rawValue
    /// JSON-encoded `[templateRaw: [originalRoomName: customName]]`. Empty
    /// object by default — rooms fall back to their built-in names.
    @AppStorage("customFloorPlanRoomNames") private var customRoomNamesJSON: String = "{}"

    private var selectedFloorPlan: FloorPlanTemplate {
        FloorPlanTemplate(rawValue: floorPlanRawValue) ?? .blank
    }

    private var roomNameOverrides: [String: String] {
        FloorPlanCustomRoomNames.names(for: selectedFloorPlan, json: customRoomNamesJSON)
    }

    /// Trail points to highlight as "Best" and "Worst" latency on the map.
    /// Only surfaced once a survey is finished so the user doesn't see a
    /// badge flicker between points during the walk — in-progress rankings
    /// would be misleading. Computed inline (single pass each) rather than
    /// pulling from `SurveyInsightsReport` so these badges still appear in
    /// the brief window before the insights report is cached and for short
    /// walks where the engine returns `nil` but we still want to show the
    /// extremes on the map.
    private var highlightedSpots: (best: TrailPoint?, worst: TrailPoint?) {
        guard viewModel.calibrationStage == .finished else { return (nil, nil) }
        let rated = viewModel.trail.filter { $0.latencyMs != nil }
        guard !rated.isEmpty else { return (nil, nil) }

        let best = rated.min(by: { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) })
        let worst = rated.max(by: { ($0.latencyMs ?? -.infinity) < ($1.latencyMs ?? -.infinity) })
        return (best, worst)
    }

    var body: some View {
        Group {
            if viewModel.calibrationStage == .finished {
                finishedLayout
            } else if viewModel.usesExpandedMapLayout {
                expandedSurveyLayout
            } else {
                calibrationLayout
            }
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.primaryText)
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

                floorPlanPicker
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

    // MARK: - Finished (Review) Layout

    /// Scrollable post-survey review with the map pinned at a fixed height, a
    /// full insights panel below it, and the same Stop/Reset/New Survey
    /// controls at the bottom. Keeps the heatmap visible for context while the
    /// user reads through what `SurveyInsightsEngine` found.
    private var finishedLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                compactSurveyHeader
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                mapCanvas(contentScale: viewModel.mapContentScale)
                    .frame(height: 300)
                    .padding(.top, 10)
                    .padding(.horizontal, 12)

                compactScaleLegend
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                insightsSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                controlButtons
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                compactFooter
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var insightsSection: some View {
        if let report = SurveyInsightsEngine.generate(
            trail: viewModel.trail,
            pointsPerMeter: viewModel.pointsPerMeter
        ) {
            SurveyInsightsView(report: report)
        } else {
            let rated = viewModel.trail.filter { $0.latencyMs != nil }.count
            SurveyInsightsPlaceholder(sampleCount: rated)
        }
    }

    private func mapCanvas(contentScale: CGFloat) -> some View {
        let spots = highlightedSpots
        return SignalCanvasView(
            points: viewModel.trail,
            current: viewModel.currentPosition,
            headingRadians: viewModel.headingRadians,
            showSurveyor: viewModel.isTracking,
            calibrationStart: viewModel.calibrationStartPoint,
            pendingReanchorPoint: viewModel.pendingReanchorPoint,
            contentScale: contentScale,
            floorPlan: selectedFloorPlan,
            roomNameOverrides: roomNameOverrides,
            bestSpot: spots.best,
            worstSpot: spots.worst,
            onMapTap: { point in
                viewModel.handleMapTap(point)
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppLogoView(size: 34)
                Text("Walk The Space")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            Text("Use AR anchoring to track movement on the floor plan, then paint signal quality directly onto the map.")
                .font(.system(size: 14))
                .foregroundStyle(theme.tertiaryText)

            trackingStatusBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactSurveyHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            AppLogoView(size: 26)
            Text("Walk The Space")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.primaryText)

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
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(theme.subtle)
        )
    }

    private var trackingStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.trackingIsReliable ? Color(red: 0.25, green: 0.86, blue: 0.43) : Color(red: 0.98, green: 0.78, blue: 0.28))
                .frame(width: 6, height: 6)
            Text(viewModel.trackingStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.subtle))
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.instructionTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Text(viewModel.instructionDetail)
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.subtle, lineWidth: 1)
                )
        )
    }

    private var compactInstructionStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.instructionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(viewModel.instructionDetail)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.subtle, lineWidth: 1)
                )
        )
    }

    // MARK: - Floor Plan Picker

    /// Lets the user pick a sample floor plan to draw behind the survey, or
    /// keep the plain default. Shown on the calibration screen so it's chosen
    /// before a walk begins; hidden once a survey is in progress to avoid
    /// re-keying the background under a live heatmap.
    private var floorPlanPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("Floor Plan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 0)

                if !selectedFloorPlan.rooms.isEmpty {
                    Button {
                        showRoomNameEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Rename Rooms")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ForEach(FloorPlanTemplate.allCases) { template in
                    floorPlanChip(template)
                }
            }

            Text(selectedFloorPlan.summary)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
        .sheet(isPresented: $showRoomNameEditor) {
            FloorPlanRoomNameEditor(
                template: selectedFloorPlan,
                customNamesJSON: $customRoomNamesJSON
            )
            .withAppTheme()
        }
    }

    private func floorPlanChip(_ template: FloorPlanTemplate) -> some View {
        let isSelected = template == selectedFloorPlan
        return Button {
            floorPlanRawValue = template.rawValue
        } label: {
            VStack(spacing: 6) {
                Image(systemName: template.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : .blue)
                Text(template.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : theme.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.blue.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.clear : Color.blue.opacity(0.25),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
                Text("Stronger / lower latency")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
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
                .foregroundStyle(theme.tertiaryText)
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
                .foregroundStyle(theme.buttonText)
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
                        .foregroundStyle(theme.primaryText)
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
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.subtle)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.cardStroke, lineWidth: 1)
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
                    .foregroundStyle(viewModel.isTracking ? theme.secondaryText : theme.quaternaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.subtle)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.cardStroke, lineWidth: 1)
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
                        .foregroundStyle(theme.primaryText)
                }
                Spacer()
                Text("\(Int(viewModel.mapRotationDegrees))°")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
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
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
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
                        .foregroundStyle(theme.primaryText)
                } else {
                    Text("— ms")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("\(viewModel.trail.count) pts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
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
                    .foregroundStyle(theme.primaryText)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Floor Plan Room Name Editor

/// Sheet presented from the Floor Plan picker that lets the user give each
/// room a personalized nickname (e.g. "Bedroom 2" → "Jamie's Room"). Writes
/// are routed through `FloorPlanCustomRoomNames` so empty/blank entries clear
/// the override rather than persisting an empty string, and the 24-character
/// cap matches the canvas label's visual budget.
private struct FloorPlanRoomNameEditor: View {
    let template: FloorPlanTemplate
    @Binding var customNamesJSON: String

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var currentOverrides: [String: String] {
        FloorPlanCustomRoomNames.names(for: template, json: customNamesJSON)
    }

    private var hasAnyOverrides: Bool {
        !currentOverrides.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Give each room a name that matches your space. Leave blank to use the default.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(template.rooms.indices, id: \.self) { idx in
                            roomRow(for: template.rooms[idx])
                        }
                    }
                    .padding(.horizontal, 16)

                    if hasAnyOverrides {
                        Button(role: .destructive) {
                            customNamesJSON = FloorPlanCustomRoomNames.resetAll(
                                for: template,
                                json: customNamesJSON
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("Reset All to Defaults")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Color(red: 0.98, green: 0.39, blue: 0.34))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.98, green: 0.39, blue: 0.34).opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(red: 0.98, green: 0.39, blue: 0.34).opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 24)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Rename Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private func roomRow(for room: FloorPlanRoom) -> some View {
        let currentValue = currentOverrides[room.name] ?? ""
        let binding = Binding<String>(
            get: { currentValue },
            set: { newValue in
                customNamesJSON = FloorPlanCustomRoomNames.setName(
                    newValue,
                    for: room.name,
                    in: template,
                    json: customNamesJSON
                )
            }
        )

        return HStack(spacing: 12) {
            Circle()
                .fill(room.tint.color.opacity(0.85))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                TextField(room.name, text: binding)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .onChange(of: binding.wrappedValue) { _, newValue in
                        if newValue.count > FloorPlanCustomRoomNames.maxNameLength {
                            binding.wrappedValue = String(newValue.prefix(FloorPlanCustomRoomNames.maxNameLength))
                        }
                    }
            }

            if !currentValue.isEmpty {
                Button {
                    binding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(room.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Survey Pro Gate

/// Wrapper around the Survey (`ContentView`) that only lets Pro users
/// through. Free users see an upsell explaining that the Survey is
/// part of Wi-Fi Buddy Pro, with a CTA that presents `PaywallView`
/// as a sheet. The authoritative check is `store.isProUser`, which is
/// derived from `Transaction.currentEntitlements` inside `ProStore`
/// (not a persisted `@AppStorage` flag), so a jailbroken user cannot
/// flip a local default to bypass the gate.
struct SurveyProGate: View {
    @ObservedObject var store: ProStore
    @Environment(\.theme) private var theme
    @State private var showPaywall = false

    var body: some View {
        Group {
            if store.isProUser {
                ContentView()
            } else {
                upsell
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store, isPresented: $showPaywall)
                .withAppTheme()
        }
    }

    private var upsell: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    AppLogoView(size: 60)
                        .padding(.top, 32)

                    HStack(spacing: 0) {
                        Text("Unlock the ")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("Survey")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.blue)
                    }

                    Text("Walk your space and paint Wi-Fi coverage onto the map.")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }

                previewCard
                    .padding(.horizontal, 20)

                proBenefitsCard
                    .padding(.horizontal, 20)

                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Get Pro for Unlimited Surveys")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(theme.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Text("Cancel anytime from your Apple ID subscriptions.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }

    private var previewCard: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Pro Preview")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.blue.opacity(0.12)))

                Spacer()
            }

            Text("See every dead zone at a glance with a live coverage heatmap painted over your own floor plan.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private var proBenefitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("With Wi-Fi Buddy Pro you get")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            benefitRow(
                icon: "infinity",
                title: "Unlimited Surveys",
                detail: "Walk any space, any time — no caps, no limits."
            )
            benefitRow(
                icon: "map.fill",
                title: "Live Coverage Heatmap",
                detail: "Paint signal quality onto your floor plan as you move."
            )
            benefitRow(
                icon: "chart.bar.doc.horizontal",
                title: "Insights & Dead-Zone Reports",
                detail: "See exactly where coverage drops off and what to do next."
            )
            benefitRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Unlimited Chats with Klaus",
                detail: "Ask your Wi-Fi sidekick anything, as often as you like."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .padding(6)
                .background(Circle().fill(Color.blue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .withAppTheme()
    }
}
