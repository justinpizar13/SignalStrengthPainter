import Combine
import CoreGraphics
import Foundation

@MainActor
final class SignalMapViewModel: ObservableObject {
    enum CalibrationStage {
        case idle
        case selectingStartPoint
        case readyToStart
        case selectingReanchorPoint
        case surveying
        /// Tracking stopped; trail and heatmap stay on screen for review.
        case finished
    }

    @Published private(set) var isTracking = false
    @Published private(set) var currentPosition: CGPoint = .zero
    @Published private(set) var latestLatencyMs: Double?
    @Published private(set) var trail: [TrailPoint] = []
    @Published private(set) var headingRadians: Double = 0
    @Published private(set) var trackingStatus = "Ready to start"
    @Published private(set) var trackingIsReliable = false
    @Published private(set) var calibrationStage: CalibrationStage = .idle
    @Published private(set) var calibrationStartPoint: CGPoint?
    @Published private(set) var pendingReanchorPoint: CGPoint?

    var mapRotationDegrees: Double {
        get { storedMapRotationDegrees }
        set { setMapRotationDegrees(newValue) }
    }

    private let arTrackingManager = ARTrackingManager()
    private let latencyProbe = LatencyProbe()

    private var pingTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var mapAnchorOffset: CGPoint = .zero
    private var lastSamplePosition: CGPoint = .zero
    private var lastSampleDate = Date.distantPast
    private var latestRelativePosition = SIMD3<Double>(repeating: 0)
    private var storedMapRotationDegrees: Double = 0
    /// Last map / AR pair for segment-based alignment (AR is world delta from session anchor).
    private var lastReanchorMap: CGPoint = .zero
    private var lastReanchorAR = SIMD3<Double>(repeating: 0)
    private var hasRefinedRotationFromLandmark = false
    /// Map-units-per-meter used when projecting AR position onto the floor plan.
    /// Exposed (read-only) so downstream analysis like `SurveyInsightsEngine`
    /// can convert trail-point distances back into real-world meters without
    /// duplicating the constant.
    let pointsPerMeter: Double = 38.0
    private let minimumLandmarkSegmentPoints: CGFloat = 25
    private let minimumLandmarkARPixels: CGFloat = 15
    /// Distance (in map points) the surveyor must move since the last logged
    /// sample before we record another. At `pointsPerMeter = 38`, 16 pt ≈
    /// 42 cm — roughly double the previous 8 pt / 21 cm spacing. Wi-Fi
    /// signal doesn't change meaningfully over 20 cm and each trail point's
    /// heat blob already has a ~2.8 m diameter, so the coarser spacing keeps
    /// the heatmap smooth while roughly halving total point count, which
    /// makes individual points much easier to tap for post-survey review.
    private let minimumSampleDistancePoints: CGFloat = 16
    /// Minimum wall-clock gap between samples. Doubled from 0.12 s so a user
    /// who's standing still (or walking very slowly near a router) doesn't
    /// pile up near-identical samples at the same spot.
    private let minimumSampleInterval: TimeInterval = 0.25

    init() {
        bindTracking()
    }

    var instructionTitle: String {
        switch calibrationStage {
        case .idle:
            return "Calibrate Before Survey"
        case .selectingStartPoint:
            return "Step 1: Pick Your Starting Spot"
        case .readyToStart:
            return "Step 2: Start Survey"
        case .selectingReanchorPoint:
            return "Re-anchor To Known Point"
        case .surveying:
            return "Survey In Progress"
        case .finished:
            return "Survey Complete"
        }
    }

    var instructionDetail: String {
        switch calibrationStage {
        case .idle:
            return "Tap Start Calibration, then choose where you are standing on the map before the survey begins."
        case .selectingStartPoint:
            return "Tap the exact place on the floor plan where you are standing right now."
        case .readyToStart:
            return "Stand on the chosen start point and tap Start Survey. AR will track your movement in real time, and you can correct drift later with known map points."
        case .selectingReanchorPoint:
            return "Tap your current real-world location on the map to re-anchor the AR path to a known point."
        case .surveying:
            return "Walk normally while keeping the phone aimed at the space around you. After you reach a known spot on the map, tap Re-anchor and tap that spot once — the first time you do this with enough distance walked, the app also learns map rotation from your path."
        case .finished:
            return "Review the path and heatmap below. Tap Start New Survey when you want to run another walk, or use Reset to clear everything."
        }
    }

    var primaryActionTitle: String {
        switch calibrationStage {
        case .idle:
            return "Start Calibration"
        case .selectingStartPoint:
            return "Tap Start Point On Map"
        case .readyToStart:
            return "Start Survey"
        case .selectingReanchorPoint:
            return "Tap Your Current Location"
        case .surveying:
            return "Surveying..."
        case .finished:
            return "Start New Survey"
        }
    }

    var canRunPrimaryAction: Bool {
        switch calibrationStage {
        case .idle:
            return true
        case .selectingStartPoint:
            return false
        case .readyToStart:
            return true
        case .selectingReanchorPoint:
            return false
        case .surveying:
            return false
        case .finished:
            return true
        }
    }

    var showsRotationControl: Bool {
        calibrationStage == .readyToStart || calibrationStage == .surveying || calibrationStage == .finished
    }

    /// Full-screen style layout: more room for the map while surveying or reviewing.
    var usesExpandedMapLayout: Bool {
        switch calibrationStage {
        case .surveying, .selectingReanchorPoint, .finished:
            return true
        case .idle, .selectingStartPoint, .readyToStart:
            return false
        }
    }

    /// Baseline zoom applied to map content so longer walks stay on the canvas (1 = normal).
    /// Users can pinch / use the zoom controls in `SignalCanvasView` to zoom in or out from this baseline,
    /// and tap the recenter button to return to it.
    var mapContentScale: CGFloat {
        usesExpandedMapLayout ? 0.72 : 1.0
    }

    func performPrimaryAction() {
        switch calibrationStage {
        case .idle:
            beginCalibration()
        case .readyToStart:
            startSurvey()
        case .finished:
            beginCalibration()
        case .selectingStartPoint, .selectingReanchorPoint, .surveying:
            break
        }
    }

    func beginCalibration() {
        resetMap()
        calibrationStage = .selectingStartPoint
        trackingStatus = arTrackingManager.isSupported
            ? "Move the phone slowly to lock tracking."
            : "AR tracking is not supported on this device."
        arTrackingManager.startSession()
    }

    func handleMapTap(_ point: CGPoint) {
        switch calibrationStage {
        case .selectingStartPoint:
            calibrationStartPoint = point
            currentPosition = point
            calibrationStage = .readyToStart
        case .selectingReanchorPoint:
            applyLandmarkReanchor(to: point)
        case .idle, .readyToStart, .surveying, .finished:
            break
        }
    }

    func startSurvey() {
        guard let start = calibrationStartPoint else { return }

        pingTimer?.invalidate()
        pingTimer = nil
        isTracking = true
        calibrationStage = .surveying
        latestLatencyMs = nil
        trail = []
        lastSampleDate = .distantPast
        lastSamplePosition = start
        mapAnchorOffset = start
        currentPosition = start
        pendingReanchorPoint = nil

        arTrackingManager.reanchorCurrentPose()
        latestRelativePosition = SIMD3<Double>(repeating: 0)
        lastReanchorMap = start
        lastReanchorAR = SIMD3<Double>(repeating: 0)
        hasRefinedRotationFromLandmark = false
        startPingLoop()
        appendCurrentSample()
    }

    func resetMap() {
        stopTracking()
        currentPosition = .zero
        latestLatencyMs = nil
        trackingIsReliable = false
        trackingStatus = "Ready to start"
        mapAnchorOffset = .zero
        calibrationStartPoint = nil
        pendingReanchorPoint = nil
        calibrationStage = .idle
        lastSamplePosition = .zero
        lastSampleDate = .distantPast
        latestRelativePosition = SIMD3<Double>(repeating: 0)
        storedMapRotationDegrees = 0
        lastReanchorMap = .zero
        lastReanchorAR = SIMD3<Double>(repeating: 0)
        hasRefinedRotationFromLandmark = false
        trail = []
    }

    func stopTracking() {
        isTracking = false
        pingTimer?.invalidate()
        pingTimer = nil
        arTrackingManager.stopSession()
    }

    /// Ends live tracking and AR; keeps trail and samples for review.
    func stopSurvey() {
        guard calibrationStage == .surveying || calibrationStage == .selectingReanchorPoint else { return }
        pingTimer?.invalidate()
        pingTimer = nil
        isTracking = false
        pendingReanchorPoint = nil
        arTrackingManager.stopSession()
        calibrationStage = .finished
        trackingStatus = "Survey stopped — review results"
        trackingIsReliable = false
    }

    func reanchorCurrentLocation() {
        guard isTracking else { return }
        pendingReanchorPoint = currentPosition
        calibrationStage = .selectingReanchorPoint
    }

    private func startPingLoop() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.latencyProbe.measureLatency { [weak self] value in
                guard let self else { return }
                self.latestLatencyMs = value
                self.refreshLatestSample()
            }
        }
        pingTimer?.tolerance = 0.1
    }

    private func bindTracking() {
        arTrackingManager.$relativePositionMeters
            .receive(on: RunLoop.main)
            .sink { [weak self] position in
                self?.applyTrackedPosition(position)
            }
            .store(in: &cancellables)

        arTrackingManager.$headingRadians
            .receive(on: RunLoop.main)
            .sink { [weak self] heading in
                self?.headingRadians = heading
            }
            .store(in: &cancellables)

        arTrackingManager.$trackingStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.trackingStatus = status
            }
            .store(in: &cancellables)

        arTrackingManager.$trackingIsReliable
            .receive(on: RunLoop.main)
            .sink { [weak self] isReliable in
                self?.trackingIsReliable = isReliable
            }
            .store(in: &cancellables)
    }

    private func applyTrackedPosition(_ relativePosition: SIMD3<Double>) {
        latestRelativePosition = relativePosition
        guard isTracking else { return }

        let trackedPoint = projectToMap(relativePosition)
        currentPosition = CGPoint(
            x: mapAnchorOffset.x + trackedPoint.x,
            y: mapAnchorOffset.y + trackedPoint.y
        )

        guard trackingIsReliable else { return }

        let distance = hypot(
            currentPosition.x - lastSamplePosition.x,
            currentPosition.y - lastSamplePosition.y
        )
        let now = Date()
        if distance >= minimumSampleDistancePoints,
           now.timeIntervalSince(lastSampleDate) >= minimumSampleInterval {
            appendCurrentSample()
        }
    }

    private func projectToMap(_ position: SIMD3<Double>) -> CGPoint {
        // Positive world +X → map +localX so strafe left/right matches body movement (was mirrored with a leading minus).
        let localX = position.x * pointsPerMeter
        let localY = position.z * pointsPerMeter
        let rotationRadians = storedMapRotationDegrees * (.pi / 180)

        let rotatedX = (localX * cos(rotationRadians)) - (localY * sin(rotationRadians))
        let rotatedY = (localX * sin(rotationRadians)) + (localY * cos(rotationRadians))
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    private func setMapRotationDegrees(_ newValue: Double, preserveCurrentPosition: Bool = true) {
        let pinnedPosition = currentPosition
        storedMapRotationDegrees = newValue

        guard preserveCurrentPosition else { return }
        guard calibrationStage == .readyToStart || calibrationStage == .surveying || calibrationStage == .finished else { return }

        let rotatedPoint = projectToMap(latestRelativePosition)
        mapAnchorOffset = CGPoint(
            x: pinnedPosition.x - rotatedPoint.x,
            y: pinnedPosition.y - rotatedPoint.y
        )
        currentPosition = pinnedPosition
    }

    private func applyLandmarkReanchor(to mapPoint: CGPoint) {
        let h = latestRelativePosition
        let dMap = CGPoint(x: mapPoint.x - lastReanchorMap.x, y: mapPoint.y - lastReanchorMap.y)
        let dAR = CGPoint(
            x: (h.x - lastReanchorAR.x) * pointsPerMeter,
            y: (h.z - lastReanchorAR.z) * pointsPerMeter
        )
        let mapLen = hypot(dMap.x, dMap.y)
        let arLen = hypot(dAR.x, dAR.y)
        if !hasRefinedRotationFromLandmark, mapLen >= minimumLandmarkSegmentPoints, arLen >= minimumLandmarkARPixels {
            let theta = atan2(dMap.y, dMap.x) - atan2(dAR.y, dAR.x)
            storedMapRotationDegrees = theta * (180 / .pi)
            hasRefinedRotationFromLandmark = true
        }

        let projectedPoint = projectToMap(h)
        mapAnchorOffset = CGPoint(
            x: mapPoint.x - projectedPoint.x,
            y: mapPoint.y - projectedPoint.y
        )
        currentPosition = mapPoint
        lastSamplePosition = mapPoint
        lastReanchorMap = mapPoint
        lastReanchorAR = h
        pendingReanchorPoint = nil
        calibrationStage = .surveying
    }

    private func appendCurrentSample() {
        trail.append(TrailPoint(position: currentPosition, latencyMs: latestLatencyMs))
        lastSamplePosition = currentPosition
        lastSampleDate = Date()
    }

    private func refreshLatestSample() {
        guard !trail.isEmpty else {
            appendCurrentSample()
            return
        }

        trail[trail.count - 1] = TrailPoint(position: currentPosition, latencyMs: latestLatencyMs)
    }
}
