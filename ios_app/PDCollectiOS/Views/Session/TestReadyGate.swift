import SwiftUI

/// The "I'm ready — start" gate for Hand Rotation (Figma 577:69) and Leg
/// Agility (577:98).
///
/// These two are the only tests where the participant has to arrange something
/// physical before the measurement means anything — phone flat in the palm,
/// phone strapped to the thigh. Every other test starts the moment the screen
/// appears, because reading the instruction and doing the thing are the same
/// motion. Here they are not, so the timer waits for a deliberate tap.
struct TestReadyGate: View {
    let test: SessionTest
    var position: Int?
    let instruction: String
    /// The line under the card, e.g. "10 seconds each hand · we count the turns".
    let measurementNote: String
    let onStart: () -> Void
    var onPause: (() -> Void)?
    let onCancel: () -> Void

    var body: some View {
        SessionTestChrome(position: position,
                          title: test.title,
                          instruction: instruction,
                          onPause: onPause,
                          onEndEarly: onCancel) {
            VStack(spacing: 0) {
                demoCard

                Text(measurementNote)
                    .font(.dopax(14))
                    .foregroundColor(.dopaxBlack90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                OnboardingPrimaryButton(title: "I'm ready — start", action: onStart)
                    .padding(.top, 32)
            }
        }
    }

    private var demoCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            demo
                .frame(height: 130)

            Spacer(minLength: 0)

            Text("Looping demo animation")
                .font(.dopax(13.5))
                .foregroundColor(.onboardingTextTertiary)
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 292)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var demo: some View {
        switch test.id {
        case "hand_turning": HandRotationDemo()
        default:             LegAgilityDemo()
        }
    }
}

/// A phone seen edge-on with a rotation arc above and below it.
///
/// Drawn rather than imported: it is three strokes, and a vector asset would
/// cost an export, a catalog entry, and a second thing to keep in sync with the
/// stroke colour.
private struct HandRotationDemo: View {
    @State private var flipped = false

    var body: some View {
        ZStack {
            arc(rotation: 0)
            arc(rotation: 180)

            Capsule()
                .stroke(Color.sessionDemoStroke, lineWidth: 5)
                .frame(width: 128, height: 22)
                .overlay(
                    Circle()
                        .fill(Color.sessionDemoStroke)
                        .frame(width: 7, height: 7)
                        .offset(x: 52)
                )
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 1, y: 0, z: 0))
        }
        .frame(width: 128, height: 130)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: flipped)
        .onAppear { flipped = true }
        .accessibilityHidden(true)
    }

    private func arc(rotation: Double) -> some View {
        ArcShape()
            .stroke(Color.sessionDemoStroke, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 96, height: 34)
            .rotationEffect(.degrees(rotation))
            .offset(y: rotation == 0 ? -34 : 34)
    }

    private struct ArcShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: -rect.maxY))
            return path
        }
    }
}

/// A leg in profile with the phone on the thigh and an arrow for the lift.
private struct LegAgilityDemo: View {
    @State private var raised = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            LegShape()
                .stroke(Color.sessionDemoStroke, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 62, height: 128)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.sessionDemoStroke)
                .frame(width: 42, height: 12)
                .offset(x: -8, y: -6)

            Image(systemName: "arrow.up")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.dopaxOrange)
                .offset(x: 92, y: raised ? 44 : 62)
        }
        .frame(width: 128, height: 130, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: raised)
        .onAppear { raised = true }
        .accessibilityHidden(true)
    }

    private struct LegShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 26))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 26, y: rect.maxY),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
    }
}
