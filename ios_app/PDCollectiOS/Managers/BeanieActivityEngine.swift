import Foundation
import CoreML
import Combine

class BeanieActivityEngine: ObservableObject {
    static let shared = BeanieActivityEngine()
    
    @Published var currentActivity: String = ""
    @Published var confidence: Double = 0.0
    @Published var allProbabilities: [Double] = Array(repeating: 0.0, count: 5)
    @Published var isReady: Bool = false
    
    let labels = ["Running", "Walking", "Sitting", "Standing", "Stairs"]
    
    private var model: MLModel?
    private var inferenceInFlight = false
    private var livePacketCount = 0
    private let inferenceQueue = DispatchQueue(label: "beanie.inference", qos: .utility)
    
    private init() {
        loadModel()
    }
    
    func reset() {
        DispatchQueue.main.async {
            self.currentActivity = ""
            self.confidence = 0.0
            self.allProbabilities = Array(repeating: 0.0, count: 5)
        }
    }
    
    private func loadModel() {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Try to load the CoreML model - look in main bundle
                guard let modelURL = Bundle.main.url(
                    forResource: "IMUTempClassifier_V5_250",
                    withExtension: "mlmodelc") ?? Bundle.main.url(
                    forResource: "IMUTempClassifier_V5_250",
                    withExtension: "mlpackage") else {
                    print("[BeanieActivityEngine] Model not found in bundle")
                    return
                }
                let compiledURL: URL
                if modelURL.pathExtension == "mlmodelc" {
                    compiledURL = modelURL
                } else {
                    compiledURL = try MLModel.compileModel(at: modelURL)
                }
                let model = try MLModel(contentsOf: compiledURL, configuration: MLModelConfiguration())
                DispatchQueue.main.async {
                    self.model = model
                    self.isReady = true
                    print("[BeanieActivityEngine] CoreML model loaded ✅")
                }
            } catch {
                print("[BeanieActivityEngine] Failed to load model: \(error)")
            }
        }
    }
    
    /// Call after each temperature packet (fires on every 2nd call to throttle)
    func startInference(
        imuMatrix: [[Float]],
        tSkin: Double,
        outerC: Double,
        heatFluxCalPerSec: Double,
        postureSeries: [[Float]],
        windowStartMs: Int64 = 0,
        windowEndMs: Int64 = 0
    ) {
        livePacketCount += 1
        guard livePacketCount % 2 == 0 else { return }  // fire every 2nd call (~10s)
        guard isReady, let model = model else { return }
        guard !inferenceInFlight else { return }
        guard imuMatrix.count >= 250 else { return }
        
        inferenceInFlight = true
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            defer { self.inferenceInFlight = false }
            
            do {
                // Build IMU multi-array [1, 250, 7]
                let imuSlice = Array(imuMatrix.suffix(250))
                let imuArray = try MLMultiArray(shape: [1, 250, 7], dataType: .float32)
                for (row, sample) in imuSlice.enumerated() {
                    for (col, val) in sample.prefix(7).enumerated() {
                        imuArray[[0, row, col] as [NSNumber]] = NSNumber(value: val)
                    }
                }
                
                // Build Temp multi-array [1, 3]
                let tempArray = try MLMultiArray(shape: [1, 3], dataType: .float32)
                tempArray[[0, 0] as [NSNumber]] = NSNumber(value: Float(tSkin))
                tempArray[[0, 1] as [NSNumber]] = NSNumber(value: Float(outerC))
                tempArray[[0, 2] as [NSNumber]] = NSNumber(value: Float(heatFluxCalPerSec))
                
                // Build Posture multi-array [1, 250, 4]
                let postureSlice = Array(postureSeries.suffix(250))
                let paddedPosture: [[Float]]
                if postureSlice.count < 250 {
                    let zeros = Array(repeating: [Float](repeating: 0, count: 4), count: 250 - postureSlice.count)
                    paddedPosture = zeros + postureSlice
                } else {
                    paddedPosture = postureSlice
                }
                let postureArray = try MLMultiArray(shape: [1, 250, 4], dataType: .float32)
                for (row, sample) in paddedPosture.enumerated() {
                    for (col, val) in sample.prefix(4).enumerated() {
                        postureArray[[0, row, col] as [NSNumber]] = NSNumber(value: val)
                    }
                }
                
                // Run inference
                let input = try MLDictionaryFeatureProvider(dictionary: [
                    "imu_input": MLFeatureValue(multiArray: imuArray),
                    "temp_input": MLFeatureValue(multiArray: tempArray),
                    "posture_input": MLFeatureValue(multiArray: postureArray)
                ])
                let output = try model.prediction(from: input)
                
                // Extract probabilities from Identity output [1,5]
                var probs = [Double](repeating: 0.0, count: 5)
                if let identity = output.featureValue(for: "Identity")?.multiArrayValue {
                    for i in 0..<5 { probs[i] = Double(truncating: identity[[0, i] as [NSNumber]]) }
                }
                
                let maxIdx = probs.indices.max(by: { probs[$0] < probs[$1] }) ?? 0
                let topLabel = self.labels[maxIdx]
                let topConf = probs[maxIdx]
                print("[BeanieActivityEngine] \(topLabel) \(Int(topConf*100))% win=\(windowStartMs/1000)..\(windowEndMs/1000)s")
                
                DispatchQueue.main.async {
                    self.currentActivity = topLabel
                    self.confidence = topConf
                    self.allProbabilities = probs
                }
            } catch {
                print("[BeanieActivityEngine] Inference error: \(error)")
            }
        }
    }
}
