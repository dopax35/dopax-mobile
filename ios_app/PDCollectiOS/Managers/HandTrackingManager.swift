import AVFoundation
import Vision
import Combine
import SwiftUI

/// Standardized camera positioning guidance status for hand/finger tracking
enum HandPositionStatus: String {
    case noHand     = "Hold hand 30-40 cm in front of camera"
    case tooFar     = "Move hand closer to camera"
    case tooClose   = "Move hand slightly farther away"
    case offCenter  = "Center hand inside frame"
    case good       = "Hand tracked — tap thumb & index finger!"

    var icon: String {
        switch self {
        case .noHand:    return "hand.raised.fill"
        case .tooFar:    return "arrow.down.right.and.arrow.up.left"
        case .tooClose:  return "arrow.up.left.and.arrow.down.right"
        case .offCenter: return "scope"
        case .good:      return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .noHand:    return .orange
        case .tooFar:    return .yellow
        case .tooClose:  return .yellow
        case .offCenter: return .orange
        case .good:      return .green
        }
    }
}

/// Represents detected 2D landmark points for overlay rendering
struct HandLandmarks {
    var thumbTip: CGPoint?
    var indexTip: CGPoint?
    var wrist: CGPoint?
    var joints: [CGPoint] = []
    var pinchDistance: CGFloat = 0.0
    var boundingBox: CGRect = .zero
}

/// Manages real-time AVCaptureSession + Vision hand pose detection for FingersTestView
class HandTrackingManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published private(set) var isRunning = false
    @Published private(set) var currentHandmarks = HandLandmarks()
    @Published private(set) var positionStatus: HandPositionStatus = .noHand
    @Published private(set) var tapCount = 0
    @Published private(set) var currentPinchDistance: CGFloat = 0.0

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.pdcollect.hand-tracking", qos: .userInitiated)
    private var handPoseRequest = VNDetectHumanHandPoseRequest()

    private var isPinched = false
    private var lastTapTime = Date.distantPast

    override init() {
        super.init()
        handPoseRequest.maximumHandCount = 1
    }

    func startTracking() {
        guard !isRunning else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            performStartTracking()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.performStartTracking()
                    }
                }
            }
        }
    }

    private func performStartTracking() {
        setupCaptureSession()
        captureQueue.async {
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stopTracking() {
        guard isRunning else { return }
        captureQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func resetTapCount() {
        DispatchQueue.main.async {
            self.tapCount = 0
            self.isPinched = false
        }
    }

    private func setupCaptureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Use front camera for hand tracking selfie view
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
                           AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        session.outputs.forEach { session.removeOutput($0) }
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if device.position == .front {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Sample Buffer Delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                DispatchQueue.main.async {
                    self.currentHandmarks = HandLandmarks()
                    self.positionStatus = .noHand
                }
                return
            }

            processHandObservation(observation)
        } catch {
            print("[HandTrackingManager] Vision error: \(error.localizedDescription)")
        }
    }

    private func processHandObservation(_ observation: VNHumanHandPoseObservation) {
        do {
            let recognizedPoints = try observation.recognizedPoints(.all)

            // Vision points are normalized (0..1) with Y=0 at bottom. Convert to top-left Y=0 for SwiftUI.
            func convertPoint(_ vnPoint: VNRecognizedPoint?) -> CGPoint? {
                guard let p = vnPoint, p.confidence > 0.3 else { return nil }
                return CGPoint(x: p.location.x, y: 1.0 - p.location.y)
            }

            let thumbTip = convertPoint(recognizedPoints[.thumbTip])
            let indexTip = convertPoint(recognizedPoints[.indexTip])
            let wrist    = convertPoint(recognizedPoints[.wrist])

            var allJoints: [CGPoint] = []
            for (_, point) in recognizedPoints where point.confidence > 0.3 {
                allJoints.append(CGPoint(x: point.location.x, y: 1.0 - point.location.y))
            }

            // Calculate pinch distance between thumb and index tip
            var dist: CGFloat = 0.0
            if let t = thumbTip, let i = indexTip {
                let dx = t.x - i.x
                let dy = t.y - i.y
                dist = sqrt(dx*dx + dy*dy)
            }

            // Calculate hand bounding box
            var minX: CGFloat = 1.0, maxX: CGFloat = 0.0
            var minY: CGFloat = 1.0, maxY: CGFloat = 0.0
            for pt in allJoints {
                minX = min(minX, pt.x)
                maxX = max(maxX, pt.x)
                minY = min(minY, pt.y)
                maxY = max(maxY, pt.y)
            }
            let bbox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            // Determine camera positioning feedback status
            let status: HandPositionStatus
            let area = bbox.width * bbox.height

            if allJoints.count < 5 {
                status = .noHand
            } else if area < 0.04 {
                status = .tooFar
            } else if area > 0.65 {
                status = .tooClose
            } else if bbox.midX < 0.2 || bbox.midX > 0.8 || bbox.midY < 0.2 || bbox.midY > 0.8 {
                status = .offCenter
            } else {
                status = .good
            }

            // Tap detection logic
            var newTapDetected = false
            if dist > 0 && dist < 0.045 {
                if !isPinched && Date().timeIntervalSince(lastTapTime) > 0.15 {
                    isPinched = true
                    newTapDetected = true
                    lastTapTime = Date()
                }
            } else if dist > 0.08 {
                isPinched = false
            }

            let landmarks = HandLandmarks(
                thumbTip: thumbTip,
                indexTip: indexTip,
                wrist: wrist,
                joints: allJoints,
                pinchDistance: dist,
                boundingBox: bbox
            )

            DispatchQueue.main.async {
                self.currentHandmarks = landmarks
                self.currentPinchDistance = dist
                self.positionStatus = status
                if newTapDetected {
                    self.tapCount += 1
                }
            }
        } catch {
            print("[HandTrackingManager] Failed to extract joints: \(error)")
        }
    }
}
