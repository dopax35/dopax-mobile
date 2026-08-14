import SwiftUI

struct SignaturePadView: View {
    @Binding var strokes: [[CGPoint]]
    @State private var currentStroke: [CGPoint] = []

    var isEmpty: Bool {
        strokes.isEmpty || strokes.allSatisfy(\.isEmpty)
    }

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes where !stroke.isEmpty {
                var path = Path()
                path.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(.onboardingAccent),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 100)
        .background(Color.white.opacity(0.01))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.onboardingAccent.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = value.location
                    if currentStroke.isEmpty {
                        currentStroke = [point]
                        strokes.append(currentStroke)
                    } else {
                        currentStroke.append(point)
                        if !strokes.isEmpty {
                            strokes[strokes.count - 1] = currentStroke
                        }
                    }
                }
                .onEnded { _ in
                    currentStroke = []
                }
        )
    }

    func exportPNG(size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: signatureExportView(size: size))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage?.pngData()
    }

    private func signatureExportView(size: CGSize) -> some View {
        Canvas { context, _ in
            let scaleX = size.width / max(size.width, 1)
            let scaleY = size.height / 100
            for stroke in strokes where !stroke.isEmpty {
                var path = Path()
                let first = CGPoint(x: stroke[0].x * scaleX, y: stroke[0].y * scaleY)
                path.move(to: first)
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
                }
                context.stroke(
                    path,
                    with: .color(.onboardingAccent),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
    }
}
