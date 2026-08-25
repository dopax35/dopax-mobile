import SwiftUI

/// Runs one test as part of a session.
///
/// The nine test screens already own their measurement, their instructions, and
/// their file writing, and none of that is worth disturbing to add a counter. So
/// the runner adds the session chrome *over* the existing screen instead of
/// rebuilding it: the participant gets "Test 4 of 9" and a Pause, and the test
/// underneath is byte-for-byte the one that has been collecting data all along.
///
/// The two tests that need the phone placed before the timer starts get the
/// ready gate first (Figma 577:69, 577:98).
struct SessionTestRunner: View {
    let test: SessionTest
    /// 1-based position in the battery, or nil for a practice run from the
    /// Tests tab — there is no position to report and nothing to pause back to.
    let position: Int?
    let total: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var gatePassed = false
    @State private var showPause = false

    var body: some View {
        Group {
            if needsGate && !gatePassed {
                gate
            } else {
                testScreen
                    .overlay(alignment: .top) { sessionBar }
            }
        }
        .sheet(isPresented: $showPause) {
            SessionPauseSheet(onResume: { showPause = false },
                              onLeave: {
                                  showPause = false
                                  dismiss()
                              })
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - Chrome

    /// Deliberately not the full `SessionTestChrome`: the test screen below
    /// already draws its own title and instruction, so overlaying the whole
    /// frame would say everything twice.
    @ViewBuilder
    private var sessionBar: some View {
        if let position {
            HStack {
                Text("Test \(position) of \(total)")
                    .font(.dopax(13))
                    .foregroundColor(.dopaxBlack70)

                Spacer()

                pauseButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private var pauseButton: some View {
        Button { showPause = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Pause")
                    .font(.dopax(13, .semibold))
            }
            .foregroundColor(.dopaxBlack90)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.06),
                                                           radius: 6, y: 2))
        }
    }

    // MARK: - Ready gate

    private var needsGate: Bool {
        test.id == "hand_turning" || test.id == "leg_agility"
    }

    @ViewBuilder
    private var gate: some View {
        TestReadyGate(test: test,
                      position: position,
                      instruction: gateInstruction,
                      measurementNote: gateNote,
                      onStart: { gatePassed = true },
                      onPause: position == nil ? nil : { showPause = true },
                      onCancel: { dismiss() })
    }

    private var gateInstruction: String {
        switch test.id {
        case "hand_turning":
            return "Hold the phone flat, screen facing the ceiling. Flip it over and back — screen down, screen up — as fast as you can."
        default:
            return "Sit down. Hold the phone firmly on your thigh. Lift your foot and stomp, as fast and high as you can."
        }
    }

    private var gateNote: String {
        switch test.id {
        case "hand_turning": return "10 seconds each hand · we count the turns"
        default:             return "10 seconds each leg · we measure the rhythm"
        }
    }

    // MARK: - The test itself

    @ViewBuilder
    private var testScreen: some View {
        switch test.id {
        case "trail_making_A":  TrailMakingTestView(part: .A)
        case "trail_making_B":  TrailMakingTestView(part: .B)
        case "spiral_tracing":  SpiralTracingView()
        case "finger_tapping":  FingerTappingView()
        case "hand_turning":    HandTurningView()
        case "voice_test":      VoiceTestView()
        case "fingers_test":    FingersTestView()
        case "facial_movement": FacialMovementTestView()
        case "leg_agility":     LegAgilityView()
        case "voice_recording": VoiceSampleView()
        default:                unknownTest
        }
    }

    /// Reachable only if `SessionTest.dailyBattery` gains an id before its
    /// screen exists. Says so rather than showing a blank screen the
    /// participant would sit and wait on.
    private var unknownTest: some View {
        ZStack {
            OnboardingBackground()
            VStack(spacing: 14) {
                Text("This test isn't available yet")
                    .font(.dopax(18, .bold))
                    .foregroundColor(.dopaxBlack90)
                OnboardingSecondaryLink(title: "Back to session") { dismiss() }
            }
        }
    }
}
