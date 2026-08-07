import Foundation
import CoreLocation
import AVFoundation
import UIKit

/// BackgroundKeepAliveManager — keeps the app awake in the background for continuous
/// CoreMotion sensor recording (50 Hz accelerometer, gyroscope, magnetometer).
///
/// Uses dual iOS background keep-alive techniques:
/// 1. Background Location Updates (`allowsBackgroundLocationUpdates = true`)
/// 2. Silent Audio Loop Playback (`AVAudioSession` + `AVAudioPlayer` loop)
class BackgroundKeepAliveManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = BackgroundKeepAliveManager()

    @Published private(set) var isLocationKeepAliveActive = false
    @Published private(set) var isAudioKeepAliveActive = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 10.0 // meters
        if #available(iOS 14.0, *) {
            locationManager.showsBackgroundLocationIndicator = false
        }
    }

    func start() {
        startLocationKeepAlive()
        startAudioKeepAlive()
    }

    func stop() {
        stopLocationKeepAlive()
        stopAudioKeepAlive()
    }

    // MARK: - Background Location Keep-Alive

    func startLocationKeepAlive() {
        let status = locationManager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        DispatchQueue.main.async { self.isLocationKeepAliveActive = true }
    }

    func stopLocationKeepAlive() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        DispatchQueue.main.async { self.isLocationKeepAliveActive = false }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.authorizationStatus = manager.authorizationStatus }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if isLocationKeepAliveActive {
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location ping received — keeps app process awake in background so CoreMotion can continue recording 50Hz data
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[BackgroundKeepAliveManager] Location update failed: \(error.localizedDescription)")
    }

    // MARK: - Background Audio Keep-Alive (Silent Loop)

    func startAudioKeepAlive() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            if audioPlayer == nil {
                let sampleRate: Double = 44100.0
                let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
                let frameCount = AVAudioFrameCount(sampleRate)
                if let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                    pcmBuffer.frameLength = frameCount
                    let wavData = createWavData(from: pcmBuffer)
                    audioPlayer = try AVAudioPlayer(data: wavData)
                    audioPlayer?.numberOfLoops = -1 // Infinite loop
                    audioPlayer?.volume = 0.01 // Silent playback
                }
            }
            audioPlayer?.play()
            DispatchQueue.main.async { self.isAudioKeepAliveActive = true }
        } catch {
            print("[BackgroundKeepAliveManager] Audio keep-alive failed: \(error.localizedDescription)")
        }
    }

    func stopAudioKeepAlive() {
        audioPlayer?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.isAudioKeepAliveActive = false }
    }

    // MARK: - WAV Generation Helper for Silent Audio

    private func createWavData(from buffer: AVAudioPCMBuffer) -> Data {
        let channels = Int(buffer.format.channelCount)
        let sampleRate = Int(buffer.format.sampleRate)
        let bitsPerSample = 16
        let numSamples = Int(buffer.frameLength)
        let dataSize = numSamples * channels * (bitsPerSample / 8)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(UInt32(36 + dataSize).littleEndianData)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(UInt32(16).littleEndianData)
        header.append(UInt16(1).littleEndianData)
        header.append(UInt16(channels).littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(UInt32(sampleRate * channels * bitsPerSample / 8).littleEndianData)
        header.append(UInt16(channels * bitsPerSample / 8).littleEndianData)
        header.append(UInt16(bitsPerSample).littleEndianData)
        header.append(contentsOf: "data".utf8)
        header.append(UInt32(dataSize).littleEndianData)

        var data = header
        data.append(Data(count: dataSize)) // All zeroes = silence
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
