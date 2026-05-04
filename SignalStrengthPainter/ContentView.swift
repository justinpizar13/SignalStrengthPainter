import SwiftUI

struct ContentView: View {
    /// StoreKit entitlement holder. Injected by the parent view so a
    /// single `ProStore` instance governs Pro across the whole app.
    /// The survey tab renders its regular chrome for free users so
    /// they can see the feature, but every attempt to actually begin
    /// a survey is hard-gated behind the trial paywall.
    @ObservedObject var store: ProStore
    @Environment(\.theme) private var theme
    @StateObject private var viewModel = SignalMapViewModel()
    @State private var showResetConfirmation = false
    @State private var showRoomNameEditor = false
    @State private var showHardPaywall = false
    /// Persisted across launches so the user's last picked floor plan is
    /// remembered. Default is `.blank` (the plain background).
    @AppStorage("floorPlanTemplate") private var floorPlanRawValue: String = FloorPlanTemplate.blank.rawValue
    /// JSON-encoded `[templateRaw: [originalRoomName: customName]]`. Empty
    /// object by default — rooms fall back to their built-in names.
    @AppStorage("customFloorPlanRoomNames") private var customRoomNamesJSON: String = "{}"
    /// Number of completed surveys across the app's lifetime. Only ever
    /// incremented for Pro (or trial) users now that the survey is fully
    /// gated; we still track it to drive the re-survey reminder
    /// scheduler on first-ever completion.
    @AppStorage("survey.completedCount") private var completedSurveyCount: Int = 0
    /// Remembers whether the "finished" stage for the current survey has
    /// already been counted so we don't double-increment if the view
    /// re-renders or the user toggles into and out of `.finished`.
    @State private var lastCountedFinishedID: ObjectIdentifier?

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
        .onChange(of: viewModel.calibrationStage) { _, newValue in
            // Count a completed survey exactly once, the moment it
            // enters `.finished`. The view model fires rapid transitions
            // elsewhere, so we guard with a one-shot token tied to the
            // view's identity.
            if newValue == .finished {
                let token = ObjectIdentifier(viewModel)
                if lastCountedFinishedID != token {
                    lastCountedFinishedID = token
                    completedSurveyCount += 1
                    // Survey reminders are a retention hook — ask for
                    // notification permission after the first real
                    // success, not at launch when the user has no
                    // context for why we'd want it.
                    SurveyReminderScheduler.shared.scheduleResurveyReminders()
                }
            } else if newValue == .idle || newValue == .selectingStartPoint {
                lastCountedFinishedID = nil
            }
        }
        .sheet(isPresented: $showHardPaywall) {
            PaywallView(store: store, isPresented: $showHardPaywall)
                .withAppTheme()
        }
    }

    /// Hard-gate the primary survey-control button for free users.
    ///
    /// Policy:
    /// - Pro users always proceed.
    /// - On transitions that start a NEW survey (`idle` / `finished`),
    ///   free users are ALWAYS shown the full-screen paywall. A single
    ///   survey is often all anyone runs, so we can't afford to give
    ///   one away — the whole flow is a trial-paywall funnel.
    /// - Mid-flow transitions (tap start point, re-anchor, stop) are
    ///   never gated — only the entry to a new survey.
    private func handlePrimaryAction() {
        let startsNewSurvey = viewModel.calibrationStage == .idle
            || viewModel.calibrationStage == .finished

        if !store.isProUser && startsNewSurvey {
            showHardPaywall = true
            return
        }

        viewModel.performPrimaryAction()
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
            // The A–F grade, dead-zone clustering and router-direction
            // hint are the real paid payoff. Free users have already
            // seen the raw heatmap above; the *report* stays locked.
            Group {
                if store.isProUser {
                    SurveyInsightsView(report: report)
                } else {
                    LockedInsightsCard {
                        showHardPaywall = true
                    }
                }
            }
            .onAppear { publishSurveyToKlaus(report) }
        } else {
            let rated = viewModel.trail.filter { $0.latencyMs != nil }.count
            SurveyInsightsPlaceholder(sampleCount: rated)
        }
    }

    /// Mirror the freshly-computed report into `KlausContextHub` so the
    /// chat assistant can speak to "your last Survey graded X" without
    /// reaching into the view model directly. Done from `.onAppear`
    /// (rather than at body-build time) so updating the published
    /// snapshot doesn't loop with a re-render.
    private func publishSurveyToKlaus(_ report: SurveyInsightsReport) {
        KlausContextHub.shared.update { ctx in
            ctx.lastSurveyGrade = report.grade.rawValue
            ctx.lastSurveyHeadline = report.grade.headline
            ctx.lastSurveyMedianMs = report.medianLatencyMs
            ctx.lastSurveyP95Ms = report.p95LatencyMs
            ctx.lastSurveyJitterMs = report.jitterMs
            ctx.lastSurveyDeadZoneCount = report.deadZones.count
            ctx.lastSurveyDistanceMeters = report.distanceWalkedMeters
            ctx.lastSurveyExcellentPct = report.excellentPercentage
            ctx.lastSurveyPoorPct = report.poorPercentage
            ctx.lastSurveyAt = Date()
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
                handlePrimaryAction()
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
/// part of WiFi Buddy Pro, with a CTA that presents `PaywallView`
/// as a sheet. The authoritative check is `store.isProUser`, which is
/// derived from `Transaction.currentEntitlements` inside `ProStore`
/// (not a persisted `@AppStorage` flag), so a jailbroken user cannot
/// flip a local default to bypass the gate.
struct SurveyProGate: View {
    @ObservedObject var store: ProStore

    var body: some View {
        // Free users now fall through to the real survey UI — the hard
        // paywall is fired inside `ContentView` on the first (and
        // post-freebie) Start Survey tap. The previous all-or-nothing
        // soft gate hid the "aha" walk entirely, which hurt trial
        // starts. We keep this wrapper purely so the rest of the app
        // can pass `store` through without knowing about the change.
        ContentView(store: store)
    }
}

// MARK: - Locked Insights Card

/// Shown below the raw heatmap after a free user's first completed
/// survey. The heatmap is their "aha"; this card is the "relief" —
/// upgrading to Pro unlocks Klaus's full report (A–F grade, dead-zone
/// clustering, router-placement hint). Branded as Klaus's report so the
/// upsell reads as "unlock the rest of Klaus's analysis" rather than a
/// generic feature wall. Tapping the CTA re-fires the same hard paywall
/// used on the Start Survey gate.
struct LockedInsightsCard: View {
    @Environment(\.theme) private var theme
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    KlausMascotView(size: 40, mode: .portrait)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("KLAUS'S FULL REPORT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                            .tracking(0.6)
                    }
                    Text("Beep boop — let me dig deeper")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                lockedRow(icon: "chart.bar.doc.horizontal", text: "A–F coverage grade for your space")
                lockedRow(icon: "mappin.slash", text: "Dead-zone clustering with exact spots")
                lockedRow(icon: "wifi", text: "Best router placement hint")
            }

            Button(action: onUnlock) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Unlock Klaus's Insights")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
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

    private func lockedRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: ProStore())
            .withAppTheme()
    }
}
