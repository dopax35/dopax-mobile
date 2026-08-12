import SwiftUI
import UserNotifications
import HealthKit

/// Full Figma onboarding wizard. Persistence gates unchanged except additive
/// `onboardingVersion` / session windows so legacy users re-enter safely.
struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var step = 0
    @State private var editingMedication: Medication?

    private var profile: UserProfile { appState.userProfile }

    private var isAboutComplete: Bool {
        (!profile.age.isEmpty || !profile.yearOfBirth.isEmpty) && !profile.gender.isEmpty
    }

    private var isTimesComplete: Bool {
        !profile.testTimeCustom.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressDots(total: 7, current: min(step + 1, 6))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                Group {
                    switch step {
                    case 0: aboutYouStep
                    case 1: medicationsStep
                    case 2: testTimesStep
                    case 3: healthAppsStep
                    case 4: keyboardPrimerStep
                    case 5: remindersPrimerStep
                    default: readyStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            // Legacy users who already completed demographics jump to test times.
            if profile.profileComplete && profile.needsOnboardingV2 && step == 0 {
                step = 2
            }
        }
        .sheet(item: $editingMedication) { med in
            MedicationEditSheet(medication: med, profile: profile)
        }
    }

    // MARK: - About you

    private var aboutYouStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About you")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
            Text("This helps us read your tests correctly.")
                .font(.system(size: 14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingFieldLabel(text: "Your name")
                    OnboardingTextField(
                        placeholder: "Optional",
                        text: Binding(get: { profile.displayName }, set: { profile.displayName = $0 })
                    )

                    OnboardingFieldLabel(text: "Year of birth")
                    OnboardingTextField(
                        placeholder: "e.g. 1957",
                        text: Binding(
                            get: { profile.yearOfBirth },
                            set: { value in
                                profile.yearOfBirth = value
                                if let y = Int(value), y > 1900 {
                                    profile.age = String(Calendar.current.component(.year, from: Date()) - y)
                                }
                            }
                        ),
                        keyboard: .numberPad
                    )

                    OnboardingFieldLabel(text: "Gender")
                    genderPicker

                    OnboardingFieldLabel(text: "Your dominant hand")
                    OnboardingSegmentRow(
                        options: ["Left", "Right"],
                        selection: Binding(
                            get: { profile.dominantHand == "Left" ? "Left" : "Right" },
                            set: { profile.dominantHand = $0 }
                        )
                    )

                    OnboardingFieldLabel(text: "Which hand is affected by Parkinson’s?")
                    OnboardingSegmentRow(
                        options: ["Left", "Right", "Both"],
                        selection: Binding(
                            get: {
                                ["Left", "Right", "Both"].contains(profile.affectedSide)
                                    ? profile.affectedSide : "Left"
                            },
                            set: { profile.affectedSide = $0 }
                        )
                    )
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }

            OnboardingPrimaryButton(title: "Continue", enabled: isAboutComplete) { step = 1 }
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private var genderPicker: some View {
        Menu {
            ForEach(["Male", "Female", "Non-binary", "Prefer not to say"], id: \.self) { option in
                Button(option) { profile.gender = option }
            }
        } label: {
            HStack {
                Text(profile.gender.isEmpty ? "Select" : profile.gender)
                    .foregroundColor(profile.gender.isEmpty ? .dopaxGray50 : .dopaxBlack90)
                Spacer()
                Image(systemName: "chevron.down").foregroundColor(.dopaxGray50)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Medications

    private var medicationsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your medications")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
            Text("So one tap can log a dose later.")
                .font(.system(size: 14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(profile.medications.enumerated()), id: \.element.id) { index, med in
                        Button { editingMedication = med } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(med.name.isEmpty ? "Medication \(index + 1)" : med.name)
                                        .foregroundColor(.dopaxBlack90)
                                        .font(.system(size: 16, weight: .semibold))
                                    if !med.dosage.isEmpty {
                                        Text(med.dosage).font(.caption).foregroundColor(.dopaxBlack70)
                                    }
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundColor(.onboardingAccent)
                            }
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    Button {
                        editingMedication = Medication(name: "", dosage: "")
                    } label: {
                        Text("+ Add another medication")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.onboardingAccent)
                    }
                    .padding(.top, 8)

                    Text("You can always change these in your Profile.")
                        .font(.system(size: 13))
                        .foregroundColor(.onboardingTextTertiary)
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }

            OnboardingPrimaryButton(title: "Continue") { step = 2 }
                .padding(.bottom, 12)
            OnboardingSecondaryLink(title: "Back", color: .onboardingTextTertiary) { step = 0 }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Test times

    private var testTimesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your three daily sessions")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
            Text("Same times every day teach us fastest.")
                .font(.system(size: 14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            VStack(spacing: 12) {
                sessionRow(title: "Morning window", subtitle: profile.testTimeMorning, locked: true)
                sessionRow(title: "Evening window", subtitle: profile.testTimeEvening, locked: true)

                VStack(alignment: .leading, spacing: 8) {
                    OnboardingFieldLabel(text: "Your window")
                    OnboardingTextField(
                        placeholder: "e.g. 14:00 or 14:00-15:00",
                        text: Binding(get: { profile.testTimeCustom }, set: { profile.testTimeCustom = $0 })
                    )
                }
                .padding(.top, 8)

                Text("A reminder arrives when each window opens. Sessions take about 4 minutes.")
                    .font(.system(size: 13))
                    .foregroundColor(.dopaxBlack70)
                    .padding(.top, 8)
            }
            .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(title: "Continue", enabled: isTimesComplete) { step = 3 }
                .padding(.bottom, 12)
            OnboardingSecondaryLink(title: "Back", color: .onboardingTextTertiary) { step = 1 }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private func sessionRow(title: String, subtitle: String, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .foregroundColor(.onboardingAccent)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.dopaxBlack90)
                Text(subtitle).font(.system(size: 13)).foregroundColor(.dopaxBlack70)
            }
            Spacer()
            if locked {
                Image(systemName: "lock.fill").foregroundColor(.dopaxGray50).font(.system(size: 14))
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Health apps

    private var healthAppsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect health apps")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
            Text("Optional — activity data helps us see the full picture.")
                .font(.system(size: 14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            VStack(spacing: 12) {
                healthRow(title: "Apple Health", subtitle: "Sleep & activity", status: profile.healthAppleStatus) {
                    requestHealthKit()
                }
                healthRow(title: "Strava", subtitle: "Workouts", status: profile.healthStravaStatus) {
                    profile.healthStravaStatus = "skipped"
                }
            }
            .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(title: "Continue") { step = 4 }
                .padding(.bottom, 12)
            OnboardingSecondaryLink(title: "Skip for now", color: .onboardingTextTertiary) {
                profile.healthAppleStatus = profile.healthAppleStatus.isEmpty ? "skipped" : profile.healthAppleStatus
                profile.healthStravaStatus = "skipped"
                step = 4
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private func healthRow(title: String, subtitle: String, status: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundColor(.dopaxBlack70)
            }
            Spacer()
            Button(status == "connected" ? "Connected" : "Connect", action: action)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.onboardingAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            profile.healthAppleStatus = "unavailable"
            return
        }
        let store = HKHealthStore()
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        store.requestAuthorization(toShare: [], read: types) { success, _ in
            DispatchQueue.main.async {
                profile.healthAppleStatus = success ? "connected" : "denied"
            }
        }
    }

    // MARK: - Interaction / keyboard

    private var keyboardPrimerStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 42))
                .foregroundColor(.onboardingAccent)
                .frame(width: 96, height: 96)
                .background(Color.white)
                .clipShape(Circle())

            Text("How you use your phone")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            Text("dopa-X reads simple interaction signals, like typing rhythm, to notice changes over time.")
                .font(.system(size: 15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            OnboardingPrimerCard(
                title: "What we never do",
                bodyText: "Never reads what you type. Never sees messages or passwords. Only rhythm and movement patterns."
            )
            .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(title: "Open Settings") {
                profile.keyboardOptIn = true
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                step = 5
            }
            OnboardingSecondaryLink(title: "Not now", color: .onboardingTextTertiary) {
                profile.keyboardOptIn = false
                step = 5
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Reminders

    private var remindersPrimerStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Image(systemName: "clock.fill")
                .font(.system(size: 42))
                .foregroundColor(.onboardingAccent)
                .frame(width: 96, height: 96)
                .background(Color.white)
                .clipShape(Circle())

            Text("Gentle reminders")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.dopaxBlack90)
                .padding(.top, 28)

            Text("dopa-X will remind you when a session window opens. Nothing else.")
                .font(.system(size: 15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            OnboardingPrimerCard(
                title: "What we never do",
                bodyText: "No marketing messages. No guilt reminders. Quiet hours are respected."
            )
            .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(title: "Continue") {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        profile.notificationsOptIn = granted
                        step = 6
                    }
                }
            }
            OnboardingSecondaryLink(title: "Not now", color: .onboardingTextTertiary) {
                profile.notificationsOptIn = false
                step = 6
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            OnboardingBrandMark(faceSize: 104, helixWidth: 170)

            HStack(spacing: 5) {
                ForEach(0..<14, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(i == 0 ? Color.onboardingAccentSoft : Color(hex: 0xE4DCF7))
                        .frame(width: 13, height: 8)
                }
            }
            .padding(.top, 22)

            Text("Your helix starts today")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(.dopaxBlack90)
                .padding(.top, 28)

            Text("For the next 14 days, every session teaches dopa-X how you move. Your first strand is waiting.")
                .font(.system(size: 15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Spacer()

            OnboardingPrimaryButton(title: "Start my first session", enabled: isAboutComplete && isTimesComplete) {
                finishProfile()
            }
            OnboardingSecondaryLink(title: "Later today", color: .onboardingTextTertiary) {
                finishProfile()
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private func finishProfile() {
        if profile.gender.isEmpty { profile.gender = "Prefer not to say" }
        if profile.age.isEmpty, let y = Int(profile.yearOfBirth), y > 1900 {
            profile.age = String(Calendar.current.component(.year, from: Date()) - y)
        }
        profile.profileComplete = true
        profile.onboardingVersion = 2

        // Firestore (primary while BOTH_ARCH=true) + Postgres (additive).
        FirebaseSyncManager.shared.saveProfileToCloud(profile: profile)
        BackendSyncManager.shared.syncProfile(profile)
    }
}

struct MedicationEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var medication: Medication
    @ObservedObject var profile: UserProfile

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Medication Name", text: $medication.name)
                    TextField("Dosage (e.g. 100mg)", text: $medication.dosage)
                }
            }
            .navigationTitle(medication.name.isEmpty ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !medication.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            var meds = profile.medications
                            if let idx = meds.firstIndex(where: { $0.id == medication.id }) {
                                meds[idx] = medication
                            } else {
                                meds.append(medication)
                            }
                            profile.medications = meds
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
