import SwiftUI

/// Overlay view drawing detected hand joints, thumb-to-index pinch distance line, and positioning guide
struct HandLandmarkOverlayView: View {
    let landmarks: HandLandmarks
    let status: HandPositionStatus

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Central Target Framing Guide Box
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        status == .good ? Color.green.opacity(0.8) : Color.white.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .frame(width: width * 0.7, height: height * 0.65)
                    .position(x: width / 2, y: height / 2)

                // Joint Dots and Connecting Lines Canvas
                Canvas { context, size in
                    // Draw bounding box if hand detected
                    if landmarks.boundingBox != .zero && !landmarks.joints.isEmpty {
                        let rect = CGRect(
                            x: landmarks.boundingBox.minX * size.width,
                            y: landmarks.boundingBox.minY * size.height,
                            width: landmarks.boundingBox.width * size.width,
                            height: landmarks.boundingBox.height * size.height
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 10)
                        context.stroke(path, with: .color(status == .good ? .green.opacity(0.6) : .orange.opacity(0.6)), lineWidth: 2)
                    }

                    // Draw all joint nodes
                    for joint in landmarks.joints {
                        let pt = CGPoint(x: joint.x * size.width, y: joint.y * size.height)
                        let dotRect = CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: dotRect), with: .color(.cyan))
                    }

                    // Highlight Thumb & Index fingertip points and distance line
                    if let thumb = landmarks.thumbTip, let index = landmarks.indexTip {
                        let tPt = CGPoint(x: thumb.x * size.width, y: thumb.y * size.height)
                        let iPt = CGPoint(x: index.x * size.width, y: index.y * size.height)

                        // Draw distance connector line
                        var linePath = Path()
                        linePath.move(to: tPt)
                        linePath.addLine(to: iPt)

                        let lineColor: Color = landmarks.pinchDistance < 0.05 ? .green : .yellow
                        context.stroke(linePath, with: .color(lineColor), lineWidth: 3)

                        // Thumb Tip (Yellow circle)
                        let tRect = CGRect(x: tPt.x - 9, y: tPt.y - 9, width: 18, height: 18)
                        context.fill(Path(ellipseIn: tRect), with: .color(.yellow))
                        context.stroke(Path(ellipseIn: tRect), with: .color(.white), lineWidth: 2)

                        // Index Tip (Magenta circle)
                        let iRect = CGRect(x: iPt.x - 9, y: iPt.y - 9, width: 18, height: 18)
                        context.fill(Path(ellipseIn: iRect), with: .color(.magenta))
                        context.stroke(Path(ellipseIn: iRect), with: .color(.white), lineWidth: 2)
                    }
                }

                // Pinch Distance Badge (if tips tracked)
                if let thumb = landmarks.thumbTip, let index = landmarks.indexTip {
                    let midX = (thumb.x + index.x) / 2 * width
                    let midY = (thumb.y + index.y) / 2 * height

                    Text(String(format: "%.1f cm", landmarks.pinchDistance * 100))
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                        .position(x: midX, y: max(midY - 24, 20))
                }
            }
        }
    }
}
