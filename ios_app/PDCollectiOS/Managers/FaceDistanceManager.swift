import AVFoundation
import Vision
import UIKit
import Foundation

/// Captures frames from the front camera every 5 seconds and runs VNDetectFaceRectanglesRequest
/// to estimate face distance — directly analogous to Android's FaceDistanceService.
///
/// Metrics captured per frame:
///   • distance_ratio  — face_width_px / frame_width_px (larger = closer)
///   • face centre (x, y) in normalised coords
///   • Vision confidence
///   • roll angle (VNFaceObservation.roll)
///   • yaw  angle (VNFaceObservation.yaw)
///
/// Collection is paused automatically when the screen turns off and resumes when it turns on,
/// matching Android's ScreenReceiver logic.
class FaceDistanceManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Published

    @Published private(set) var isRunning        = false
    @Published private(set) var lastSample: FaceDistanceSample?
    @Published private(set) var samplesCollected = 0

    // MARK: - Private

    private let session       = AVCaptureSession()
    private let videoOutput   = AVCaptureVideoDataOutput()
    private let captureQueue  = DispatchQueue(label: "com.pdcollect.face-capture", qos: .userInitiated)
    private var dataManager: DataManager?
    private var tokens: [NSObjectProtocol] = []

    /// Only process one frame every 1 second (Android captures every 1s)
    private var nextCaptureTime: Date = .distantPast
    private let captureInterval: TimeInterval = 1

    // MARK: - Public API

    func start(dataManager: DataManager) {
        guard !isRunning else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            // Permission must be granted before calling start() — request happens
            // from UI via AVCaptureDevice.requestAccess(for:completionHandler:)
            return
        }

        self.dataManager = dataManager
        setupSession()

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

        captureQueue.async { self.session.startRunning() }
        DispatchQueue.main.async { self.isRunning = true }
    }

    func stop() {
        captureQueue.async { self.session.stopRunning() }
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Setup

    private func setupSession() {
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    }

    private func pauseSession()  { captureQueue.async { if self.session.isRunning { self.session.stopRunning() } } }
    private func resumeSession() { captureQueue.async { if !self.session.isRunning { self.session.startRunning() } } }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now >= nextCaptureTime else { return }
        nextCaptureTime = now.addingTimeInterval(captureInterval)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .leftMirrored,
                                            options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first else { return }

        let frameW = Float(CVPixelBufferGetWidth(pixelBuffer))
        let bbox   = observation.boundingBox  // normalised (0,1) with origin bottom-left

        // Mirror Android: distance_ratio = face_width_px / frame_width_px
        let faceWidthPx = Float(bbox.width) * frameW
        let distanceRatio = frameW > 0 ? faceWidthPx / frameW : 0

        let centreX = Float(bbox.midX)
        let centreY = Float(1 - bbox.midY) // flip to top-left origin

        let rollDeg: Float
        let yawDeg: Float
        if #available(iOS 16.0, *) {
            rollDeg = Float((observation.roll?.doubleValue ?? 0) * 180 / .pi)
            yawDeg  = Float((observation.yaw?.doubleValue  ?? 0) * 180 / .pi)
        } else {
            rollDeg = 0; yawDeg = 0
        }

        let sample = FaceDistanceSample(
            timestampMs: Int64(now.timeIntervalSince1970 * 1000),
            distanceRatio: distanceRatio,
            faceX: centreX,
            faceY: centreY,
            confidence: Float(observation.confidence),
            roll: rollDeg,
            yaw: yawDeg
        )

        DispatchQueue.main.async { self.lastSample = sample; self.samplesCollected += 1 }
        dataManager?.writeFaceSample(sample)
    }
}
