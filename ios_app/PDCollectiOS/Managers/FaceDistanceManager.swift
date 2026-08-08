import AVFoundation
import Vision
import ARKit
import UIKit
import Foundation

/// Captures front camera / ARKit frames to estimate face distance, eye blinks, and pupil gaze tracking —
/// logging both `FaceDistanceSample` (face_distance.csv) and `GazeSample` (gaze_tracking.csv).
///
/// Features:
///   • ARKit `ARFaceTrackingConfiguration` integration for devices with TrueDepth camera:
///     - Precise Left & Right pupil gaze vectors (yaw & pitch angles)
///     - 3D look-at point (X, Y, Z)
///     - Precise per-eye blink / open state (eyeBlinkLeft, eyeBlinkRight)
///   • Vision framework (`VNDetectFaceLandmarksRequest`) fallback for devices without ARKit TrueDepth:
///     - Pupil position relative to eye landmarks
///     - Face distance ratio, roll, and yaw angles
///
/// Collection is paused automatically when the app enters background and resumes when in foreground.
class FaceDistanceManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, ARSessionDelegate {

    // MARK: - Published

    @Published private(set) var isRunning        = false
    @Published private(set) var lastSample: FaceDistanceSample?
    @Published private(set) var lastGazeSample: GazeSample?
    @Published private(set) var samplesCollected = 0

    // MARK: - Private

    let arSession     = ARSession()
    private(set) var avSession = AVCaptureSession()
    private let videoOutput   = AVCaptureVideoDataOutput()
    private let captureQueue  = DispatchQueue(label: "com.pdcollect.face-capture", qos: .userInitiated)
    private var dataManager: DataManager?
    private var tokens: [NSObjectProtocol] = []
    private var useARKit      = false

    /// Capture interval (process 1 frame per second)
    private var nextCaptureTime: Date = .distantPast
    private let captureInterval: TimeInterval = 1.0

    // MARK: - Public API

    func start(dataManager: DataManager) {
        guard !isRunning else { return }
        self.dataManager = dataManager

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            performStart()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.performStart()
                    }
                }
            }
        }
    }

    private func performStart() {
        setupAVSession()
        captureQueue.async { self.avSession.startRunning() }

        if ARFaceTrackingConfiguration.isSupported {
            useARKit = true
            setupARKitSession()
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = true
            arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        } else {
            useARKit = false
        }

        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.pauseSession() }
        )
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.resumeSession() }
        )

        DispatchQueue.main.async { self.isRunning = true }
    }

    func stop() {
        if useARKit {
            arSession.pause()
        }
        captureQueue.async { self.avSession.stopRunning() }
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Setup

    private func setupARKitSession() {
        arSession.delegate = self
    }

    private func setupAVSession() {
        avSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input  = try? AVCaptureDeviceInput(device: device),
              avSession.canAddInput(input)
        else { return }

        avSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if avSession.canAddOutput(videoOutput) { avSession.addOutput(videoOutput) }
    }

    private func pauseSession() {
        if useARKit {
            arSession.pause()
        } else {
            captureQueue.async { if self.avSession.isRunning { self.avSession.stopRunning() } }
        }
    }

    private func resumeSession() {
        if useARKit {
            let config = ARFaceTrackingConfiguration()
            arSession.run(config, options: [])
        } else {
            captureQueue.async { if !self.avSession.isRunning { self.avSession.startRunning() } }
        }
    }

    // MARK: - ARSessionDelegate (ARKit Gaze & Pupil Tracking)

    /// Without these three callbacks, an ARSession that fails or is interrupted (phone call,
    /// Control Center camera access, thermal throttling, another app briefly taking the camera)
    /// stops delivering frames forever — `isRunning` stays true but no more samples are ever
    /// written, which is silent data loss for a study relying on continuous collection.

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard useARKit, isRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isRunning, self.useARKit else { return }
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = true
            self.arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        // ARKit pauses tracking automatically; nothing to do here — we resume in
        // sessionInterruptionEnded(_:) below.
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard useARKit, isRunning else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard useARKit else { return }
        let now = Date()
        guard now >= nextCaptureTime else { return }
        nextCaptureTime = now.addingTimeInterval(captureInterval)

        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        let timestampMs = Int64(now.timeIntervalSince1970 * 1000)
        let blendShapes = faceAnchor.blendShapes

        // Extract Eye Blink (0.0 = closed, 1.0 = open)
        let leftBlinkVal = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let rightBlinkVal = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        let leftOpenProb = 1.0 - leftBlinkVal
        let rightOpenProb = 1.0 - rightBlinkVal

        // Extract Left & Right Pupil Gaze Direction Angles (yaw & pitch)
        let leftLookOut = blendShapes[.eyeLookOutLeft]?.floatValue ?? 0
        let leftLookIn = blendShapes[.eyeLookInLeft]?.floatValue ?? 0
        let leftLookUp = blendShapes[.eyeLookUpLeft]?.floatValue ?? 0
        let leftLookDown = blendShapes[.eyeLookDownLeft]?.floatValue ?? 0

        let rightLookOut = blendShapes[.eyeLookOutRight]?.floatValue ?? 0
        let rightLookIn = blendShapes[.eyeLookInRight]?.floatValue ?? 0
        let rightLookUp = blendShapes[.eyeLookUpRight]?.floatValue ?? 0
        let rightLookDown = blendShapes[.eyeLookDownRight]?.floatValue ?? 0

        let leftGazeX = leftLookOut - leftLookIn
        let leftGazeY = leftLookUp - leftLookDown
        let rightGazeX = rightLookIn - rightLookOut
        let rightGazeY = rightLookUp - rightLookDown

        // 3D Look-at point
        let lookAt = faceAnchor.lookAtPoint

        let gazeSample = GazeSample(
            timestampMs: timestampMs,
            leftGazeX: leftGazeX,
            leftGazeY: leftGazeY,
            rightGazeX: rightGazeX,
            rightGazeY: rightGazeY,
            leftBlink: leftOpenProb,
            rightBlink: rightOpenProb,
            lookAtX: lookAt.x,
            lookAtY: lookAt.y,
            lookAtZ: lookAt.z,
            method: "arkit_truedepth"
        )

        // Calculate distance ratio and orientation from head transform.
        // Distance is measured from the *current camera position*, not the ARKit world
        // origin — the origin is fixed at session start, so measuring from it would drift
        // as soon as the participant's hand moves the phone even slightly.
        let transform = faceAnchor.transform
        let cameraTranslation = session.currentFrame?.camera.transform.columns.3
        let dx = transform.columns.3.x - (cameraTranslation?.x ?? 0)
        let dy = transform.columns.3.y - (cameraTranslation?.y ?? 0)
        let dz = transform.columns.3.z - (cameraTranslation?.z ?? 0)
        let distanceMeters = sqrt(dx * dx + dy * dy + dz * dz)
        let distanceRatio = distanceMeters > 0 ? (0.35 / distanceMeters) : 0 // normalized ratio proxy

        let pitch = atan2(transform.columns.2.y, transform.columns.2.z) * 180 / .pi
        let yaw   = atan2(transform.columns.0.z, transform.columns.2.z) * 180 / .pi
        let roll  = atan2(transform.columns.1.x, transform.columns.1.y) * 180 / .pi

        let distanceSample = FaceDistanceSample(
            timestampMs: timestampMs,
            distanceRatio: Float(distanceRatio),
            faceX: transform.columns.3.x,
            faceY: transform.columns.3.y,
            confidence: 1.0,
            roll: Float(roll),
            yaw: Float(yaw)
        )

        DispatchQueue.main.async {
            self.lastSample = distanceSample
            self.lastGazeSample = gazeSample
            self.samplesCollected += 1
        }

        dataManager?.writeFaceSample(distanceSample)
        dataManager?.writeGazeSample(gazeSample)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Vision Fallback)

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !useARKit else { return }
        let now = Date()
        guard now >= nextCaptureTime else { return }
        nextCaptureTime = now.addingTimeInterval(captureInterval)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                             orientation: .leftMirrored,
                                             options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first else { return }

        let frameW = Float(CVPixelBufferGetWidth(pixelBuffer))
        let bbox   = observation.boundingBox  // normalised (0,1) with origin bottom-left

        let faceWidthPx = Float(bbox.width) * frameW
        let distanceRatio = frameW > 0 ? faceWidthPx / frameW : 0

        let centreX = Float(bbox.midX)
        let centreY = Float(1 - bbox.midY)

        let rollDeg: Float
        let yawDeg: Float
        if #available(iOS 16.0, *) {
            rollDeg = Float((observation.roll?.doubleValue ?? 0) * 180 / .pi)
            yawDeg  = Float((observation.yaw?.doubleValue  ?? 0) * 180 / .pi)
        } else {
            rollDeg = 0; yawDeg = 0
        }

        let timestampMs = Int64(now.timeIntervalSince1970 * 1000)

        let distanceSample = FaceDistanceSample(
            timestampMs: timestampMs,
            distanceRatio: distanceRatio,
            faceX: centreX,
            faceY: centreY,
            confidence: Float(observation.confidence),
            roll: rollDeg,
            yaw: yawDeg
        )

        // Vision Pupil Landmark Extraction
        var leftGazeX: Float = 0
        var leftGazeY: Float = 0
        var rightGazeX: Float = 0
        var rightGazeY: Float = 0

        if let landmarks = observation.landmarks {
            if let leftPupil = landmarks.leftPupil {
                let points = leftPupil.normalizedPoints
                if let pt = points.first {
                    leftGazeX = Float(pt.x - 0.5)
                    leftGazeY = Float(pt.y - 0.5)
                }
            }
            if let rightPupil = landmarks.rightPupil {
                let points = rightPupil.normalizedPoints
                if let pt = points.first {
                    rightGazeX = Float(pt.x - 0.5)
                    rightGazeY = Float(pt.y - 0.5)
                }
            }
        }

        let gazeSample = GazeSample(
            timestampMs: timestampMs,
            leftGazeX: leftGazeX,
            leftGazeY: leftGazeY,
            rightGazeX: rightGazeX,
            rightGazeY: rightGazeY,
            leftBlink: 1.0,
            rightBlink: 1.0,
            lookAtX: 0,
            lookAtY: 0,
            lookAtZ: 0,
            method: "vision_landmarks_fallback"
        )

        DispatchQueue.main.async {
            self.lastSample = distanceSample
            self.lastGazeSample = gazeSample
            self.samplesCollected += 1
        }

        dataManager?.writeFaceSample(distanceSample)
        dataManager?.writeGazeSample(gazeSample)
    }
}
