import Foundation

/// A face-distance sample from the front camera — mirrors Android's face_distance.csv format.
/// Uses Vision framework (available on all iPhones) instead of ARKit TrueDepth.
struct FaceDistanceSample {
    let timestampMs: Int64       // epoch millis
    let distanceRatio: Float     // face_width_px / frame_width_px (larger = closer, like Android)
    let faceX: Float             // normalised bounding-box centre X (0–1)
    let faceY: Float             // normalised bounding-box centre Y (0–1)
    let confidence: Float        // Vision observation confidence (0–1)
    let roll: Float              // face roll angle in degrees (positive = clockwise)
    let yaw: Float               // face yaw angle in degrees (positive = turning left)

    var csvRow: String {
        "\(timestampMs),"
        + "\(String(format: "%.4f", distanceRatio)),"
        + "\(String(format: "%.4f", faceX)),"
        + "\(String(format: "%.4f", faceY)),"
        + "\(String(format: "%.3f", confidence)),"
        + "\(String(format: "%.2f", roll)),"
        + "\(String(format: "%.2f", yaw))\n"
    }
}
