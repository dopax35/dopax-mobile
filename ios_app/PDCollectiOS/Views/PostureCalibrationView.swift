import SwiftUI
import Foundation

/// Minimal posture-calibration wizard — SwiftUI counterpart to Android's
/// PostureCalibrationActivity.kt. Walks the user through 5 head positions
/// (neutral, left, right, chin-down, look-up), capturing the live
/// Madgwick-filter gravity vector at each (via the shared BeaniePostureEngine,
/// fed continuously by BeanieBluetoothService while connected), then derives +
/// saves a PostureCalibrationProfile using the same axis-frame math as the
/// reference iOS/Android calibration flows.
///
/// Deliberately simple — visual instructions + countdown only, no voice
/// synthesis, beep tones, or waveform animation. No posture history/charts UI
/// exists in this app (by design), so this screen's only job is to produce a
/// valid calibration.
struct PostureCalibrationView: View {
    @Environment(\.dismiss) private var dismiss

    private struct CalStep {
        let title: String
        let instruction: String
        let holdSec: Int
        let capture: CaptureKind
    }

    private enum CaptureKind { case neutral, left, right, chin, up }

    private let steps: [CalStep] = [
        CalStep(title: "Step 1 of 5",
                instruction: "Sit or stand upright. Head balanced, chin level, shoulders relaxed.",
                holdSec: 8, capture: .neutral),
        CalStep(title: "Step 2 of 5",
                instruction: "Return to upright, then turn your head to look as far LEFT as comfortable.",
                holdSec: 6, capture: .left),
        CalStep(title: "Step 3 of 5",
                instruction: "Return to upright, then turn your head to look as far RIGHT as comfortable.",
                holdSec: 6, capture: .right),
        CalStep(title: "Step 4 of 5",
                instruction: "Return to upright, then slowly lower your chin all the way down to your chest.",
                holdSec: 6, capture: .chin),
        CalStep(title: "Step 5 of 5",
                instruction: "Return to upright, then tilt your head back and look up at the ceiling.",
                holdSec: 6, capture: .up)
    ]

    private enum Phase { case intro, gettingReady, holding, captured, failed, done }

    @State private var stepIndex = 0
    @State private var phase: Phase = .intro
    @State private var countdown = 0
    @State private var failureMessage = ""
    @State private var timer: Timer?

    // Captured values
    @State private var neutralGrav: (x: Double, y: Double, z: Double)?
    @State private var neutralPitch: Double?
    @State private var leftGrav: (x: Double, y: Double, z: Double)?
    @State private var leftGz: Double?
    @State private var rightGrav: (x: Double, y: Double, z: Double)?
    @State private var rightGz: Double?
    @State private var chinGrav: (x: Double, y: Double, z: Double)?
    @State private var chinPitch: Double?
    @State private var upGrav: (x: Double, y: Double, z: Double)?
    @State private var upPitch: Double?

    private let engine = BeaniePostureEngine.shared

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(min(stepIndex, steps.count)), total: Double(steps.count))
                .padding(.top, 8)

            Text(headerTitle)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(bodyText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if phase == .gettingReady || phase == .holding {
                Text("\(countdown)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.dopaxBlue)
            }

            if phase == .captured {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.dopaxStatusSuccess)
            }

            Spacer()

            actionButton
                .frame(maxWidth: .infinity)

            Button("Cancel") { stopTimer(); dismiss() }
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(24)
        .onDisappear { stopTimer() }
    }

    // MARK: - Text content

    private var headerTitle: String {
        switch phase {
        case .intro: return "Posture Calibration"
        case .failed: return "Calibration Failed"
        case .done: return "Calibration Complete"
        default: return stepIndex < steps.count ? steps[stepIndex].title : ""
        }
    }

    private var bodyText: String {
        switch phase {
        case .intro:
            return "This takes about a minute. You'll be asked to hold 5 head positions " +
                "briefly. Make sure the Beanie is on and connected before starting."
        case .failed:
            return failureMessage
        case .done:
            return "Your posture thresholds have been saved."
        default:
            return stepIndex < steps.count ? steps[stepIndex].instruction : ""
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .intro:
            Button("Begin Calibration") { beginFlow() }
                .buttonStyle(.borderedProminent)
        case .gettingReady, .holding:
            Button("Please wait\u{2026}") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
        case .captured:
            if stepIndex + 1 >= steps.count {
                Button("Finishing\u{2026}") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else {
                Button("Next Position") { advance() }
                    .buttonStyle(.borderedProminent)
            }
        case .failed:
            Button("Try Again") { resetCaptures(); phase = .intro }
                .buttonStyle(.borderedProminent)
        case .done:
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Flow

    private func beginFlow() {
        guard engine.currentAbsolutePitch() != nil else {
            failureMessage = "Beanie isn't sending motion data yet. Make sure it's connected and try again."
            phase = .failed
            return
        }
        stepIndex = 0
        runStep()
    }

    private func runStep() {
        phase = .gettingReady
        countdown = 3
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if countdown > 1 {
                countdown -= 1
            } else {
                t.invalidate()
                startHold()
            }
        }
    }

    private func startHold() {
        phase = .holding
        let step = steps[stepIndex]
        countdown = step.holdSec
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if countdown > 1 {
                countdown -= 1
            } else {
                t.invalidate()
                capture()
            }
        }
    }

    private func capture() {
        let step = steps[stepIndex]
        let grav = engine.currentGravityVector()
        let pitch = engine.currentAbsolutePitch()

        switch step.capture {
        case .neutral: neutralGrav = grav; neutralPitch = pitch
        case .left: leftGrav = grav; leftGz = engine.meanGzOverWindow(step.holdSec)
        case .right: rightGrav = grav; rightGz = engine.meanGzOverWindow(step.holdSec)
        case .chin: chinGrav = grav; chinPitch = pitch
        case .up: upGrav = grav; upPitch = pitch
        }

        phase = .captured
        if stepIndex + 1 >= steps.count {
            finalize()
        }
    }

    private func advance() {
        stepIndex += 1
        runStep()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Finalize: derive axis frame + validate + save

    private func finalize() {
        guard let neutral = neutralGrav, let chin = chinGrav, let nPitch = neutralPitch else {
            failureMessage = "Calibration incomplete. Please try again."
            phase = .failed
            return
        }

        let gravDistance = dist(neutral, chin)
        // 0.30 ≈ 18° of actual head movement (2·sin(9°) ≈ 0.313) — same
        // threshold used by the reference iOS/Android calibration flows.
        guard gravDistance >= 0.30 else {
            let angleDeg = 2.0 * asin(min(gravDistance / 2.0, 1.0)) * 180.0 / .pi
            failureMessage = String(
                format: "Head movement too small (%.0f\u{00B0} detected, need at least 18\u{00B0}). " +
                    "Make sure the beanie is on firmly and bring your chin all the way to " +
                    "your chest next time.",
                angleDeg
            )
            phase = .failed
            return
        }

        var profile = PostureCalibrationProfile()
        profile.neutralPitchDeg = nPitch
        profile.pitchRangeDeg = abs((chinPitch ?? nPitch) - nPitch)
        profile.forwardPitchSign = (chinPitch ?? nPitch) > nPitch ? 1.0 : -1.0
        if let lgz = leftGz, abs(lgz) > 3 {
            profile.leftTurnGzSign = lgz > 0 ? 1.0 : -1.0
        }
        if let up = upPitch {
            profile.upPitchRangeDeg = abs(up - nPitch)
        }

        profile.neutralGravX = neutral.x
        profile.neutralGravY = neutral.y
        profile.neutralGravZ = neutral.z

        if let axis = makeAxis(from: neutral, to: chin) {
            profile.fwdAxisX = axis.x; profile.fwdAxisY = axis.y; profile.fwdAxisZ = axis.z
            profile.fwdRange = axis.range
            let dot = neutral.x * chin.x + neutral.y * chin.y + neutral.z * chin.z
            profile.gravTiltRangeDeg = acos(min(1.0, max(-1.0, dot))) * 180.0 / .pi
        }

        if let up = upGrav, let axis = makeAxis(from: neutral, to: up) {
            profile.backAxisX = axis.x; profile.backAxisY = axis.y; profile.backAxisZ = axis.z
            profile.backRange = axis.range
        }

        if let left = leftGrav, let right = rightGrav {
            let dx = left.x - right.x, dy = left.y - right.y, dz = left.z - right.z
            let mag = sqrt(dx * dx + dy * dy + dz * dz)
            if mag > 0.01 {
                profile.latAxisX = dx / mag; profile.latAxisY = dy / mag; profile.latAxisZ = dz / mag
                profile.latHalfRange = mag / 2.0
            }
        }

        profile.calibratedAt = Date().timeIntervalSince1970
        engine.applyCalibration(profile)

        phase = .done
    }

    private func resetCaptures() {
        neutralGrav = nil; neutralPitch = nil
        leftGrav = nil; leftGz = nil
        rightGrav = nil; rightGz = nil
        chinGrav = nil; chinPitch = nil
        upGrav = nil; upPitch = nil
    }

    private func dist(_ a: (x: Double, y: Double, z: Double), _ b: (x: Double, y: Double, z: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// Returns (ux, uy, uz, magnitude) or nil if the movement was too small to be meaningful.
    private func makeAxis(
        from: (x: Double, y: Double, z: Double),
        to: (x: Double, y: Double, z: Double)
    ) -> (x: Double, y: Double, z: Double, range: Double)? {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let mag = sqrt(dx * dx + dy * dy + dz * dz)
        guard mag > 0.01 else { return nil }
        return (dx / mag, dy / mag, dz / mag, mag)
    }
}

#Preview {
    PostureCalibrationView()
}
