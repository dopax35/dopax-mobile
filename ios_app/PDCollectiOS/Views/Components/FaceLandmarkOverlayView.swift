import SwiftUI

/// Standardized camera positioning guidance status for face tracking
enum FacePositionStatus: String {
    case noFace     = "Position face in front of camera"
    case tooFar     = "Move closer to camera"
    case tooClose   = "Move slightly farther away"
    case offCenter  = "Center face inside target oval"
    case good       = "Face aligned — hold still"

    var icon: String {
        switch self {
        case .noFace:    return "person.crop.circle.badge.exclamationmark"
        case .tooFar:    return "plus.magnifyingglass"
        case .tooClose:  return "minus.magnifyingglass"
        case .offCenter: return "arrow.up.and.down.and.arrow.left.and.right"
        case .good:      return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .noFace:    return .orange
        case .tooFar:    return .yellow
        case .tooClose:  return .yellow
        case .offCenter: return .orange
        case .good:      return .green
        }
    }
}

/// Overlay view drawing facial landmarks, bounding box, and central positioning oval
struct FaceLandmarkOverlayView: View {
    let sample: FaceDistanceSample?
    let status: FacePositionStatus

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Central Face Positioning Oval Guide
                Ellipse()
                    .stroke(
                        status == .good ? Color.green.opacity(0.85) : Color.white.opacity(0.4),
                        style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                    )
                    .frame(width: width * 0.65, height: height * 0.55)
                    .position(x: width / 2, y: height / 2)

                // Face Landmarks and Bounding Box Canvas
                Canvas { context, size in
                    guard let face = sample else { return }

                    // Face center point normalized (0..1)
                    let cX = CGFloat(face.faceX) * size.width
                    let cY = CGFloat(face.faceY) * size.height
                    let boxWidth = CGFloat(face.distanceRatio) * size.width * 1.6
                    let boxHeight = boxWidth * 1.3

                    let faceRect = CGRect(
                        x: cX - boxWidth / 2,
                        y: cY - boxHeight / 2,
                        width: boxWidth,
                        height: boxHeight
                    )

                    // Draw face bounding box
                    let boxPath = Path(roundedRect: faceRect, cornerRadius: 16)
                    let strokeColor: Color = status == .good ? .green : .orange
                    context.stroke(boxPath, with: .color(strokeColor), lineWidth: 2)

                    // Draw simulated facial feature landmarks (Eyes, Nose, Mouth)
                    let leftEye  = CGPoint(x: cX - boxWidth * 0.2, y: cY - boxHeight * 0.15)
                    let rightEye = CGPoint(x: cX + boxWidth * 0.2, y: cY - boxHeight * 0.15)
                    let nose     = CGPoint(x: cX, y: cY)
                    let mouth    = CGPoint(x: cX, y: cY + boxHeight * 0.22)

                    // Eye dots
                    context.fill(Path(ellipseIn: CGRect(x: leftEye.x - 5, y: leftEye.y - 5, width: 10, height: 10)), with: .color(.cyan))
                    context.fill(Path(ellipseIn: CGRect(x: rightEye.x - 5, y: rightEye.y - 5, width: 10, height: 10)), with: .color(.cyan))
                    // Nose dot
                    context.fill(Path(ellipseIn: CGRect(x: nose.x - 4, y: nose.y - 4, width: 8, height: 8)), with: .color(.yellow))
                    // Mouth arc
                    var mouthPath = Path()
                    mouthPath.addArc(center: mouth, radius: boxWidth * 0.15, startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
                    context.stroke(mouthPath, with: .color(.green), lineWidth: 2)
                }

                // Face Distance Indicator Badge
                if let face = sample {
                    let estDistanceCm = Int(max(20, (0.45 / max(0.1, Double(face.distanceRatio))) * 40))
                    VStack(spacing: 2) {
                        Text("\(estDistanceCm) cm")
                            .font(.caption).bold()
                        Text("Face Distance")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                    .position(x: width / 2, y: height * 0.15)
                }
            }
        }
    }
}
