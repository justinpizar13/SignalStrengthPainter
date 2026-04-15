import ARKit
import Foundation
import simd

@MainActor
final class ARTrackingManager: NSObject, ObservableObject {
    @Published private(set) var isSupported = ARWorldTrackingConfiguration.isSupported
    @Published private(set) var relativePositionMeters = SIMD3<Double>(repeating: 0)
    @Published private(set) var headingRadians: Double = 0
    @Published private(set) var trackingStatus = "Ready to start"
    @Published private(set) var trackingIsReliable = false

    private let session = ARSession()
    private var latestCameraTransform: simd_float4x4?
    private var originTransform: simd_float4x4?
    /// World-space camera position at the last anchor (not the composed matrix translation).
    private var originWorldPosition: SIMD3<Double>?

    override init() {
        super.init()
        session.delegate = self
    }

    func startSession() {
        guard isSupported else {
            trackingStatus = "AR tracking is not supported on this device."
            trackingIsReliable = false
            return
        }

        relativePositionMeters = SIMD3<Double>(repeating: 0)
        headingRadians = 0
        latestCameraTransform = nil
        originTransform = nil
        originWorldPosition = nil
        trackingStatus = "Move the phone slowly to lock tracking."
        trackingIsReliable = false

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        session.pause()
        trackingIsReliable = false
    }

    func reanchorCurrentPose() {
        guard let latestCameraTransform else { return }
        originTransform = latestCameraTransform
        let t = latestCameraTransform.columns.3
        originWorldPosition = SIMD3(Double(t.x), Double(t.y), Double(t.z))
        relativePositionMeters = SIMD3<Double>(repeating: 0)
    }
}

extension ARTrackingManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.handle(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            self.updateTrackingState(camera.trackingState)
        }
    }
}

@MainActor
private extension ARTrackingManager {
    func handle(frame: ARFrame) {
        latestCameraTransform = frame.camera.transform
        let current = frame.camera.transform.columns.3
        let currentWorld = SIMD3(Double(current.x), Double(current.y), Double(current.z))

        if originTransform == nil {
            originTransform = frame.camera.transform
            originWorldPosition = currentWorld
        }

        updateTrackingState(frame.camera.trackingState)

        guard let originWorldPosition else { return }
        // True world-space displacement from anchor. Matrix-column translation from
        // inv(T0)*T1 is not the same as (p1 - p0) when orientation changes, and was
        // collapsing motion into an apparent single direction for map projection.
        relativePositionMeters = currentWorld - originWorldPosition

        // Camera forward projected onto the floor plane.
        let forward = simd_normalize(SIMD3<Double>(
            -Double(frame.camera.transform.columns.2.x),
            0,
            -Double(frame.camera.transform.columns.2.z)
        ))
        if forward.x.isFinite, forward.z.isFinite {
            headingRadians = atan2(forward.z, forward.x)
        }
    }

    func updateTrackingState(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            trackingStatus = "Tracking locked"
            trackingIsReliable = true
        case .notAvailable:
            trackingStatus = "Tracking unavailable"
            trackingIsReliable = false
        case .limited(let reason):
            trackingIsReliable = false
            switch reason {
            case .initializing:
                trackingStatus = "Initializing AR tracking..."
            case .excessiveMotion:
                trackingStatus = "Move the phone more slowly."
            case .insufficientFeatures:
                trackingStatus = "Point at textured surfaces for better tracking."
            case .relocalizing:
                trackingStatus = "Re-localizing your position..."
            @unknown default:
                trackingStatus = "Tracking is temporarily limited."
            }
        }
    }
}
