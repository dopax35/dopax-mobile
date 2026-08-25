import SwiftUI
import UserNotifications
import HealthKit

/// Full Figma onboarding wizard. Persistence gates unchanged except additive
/// `onboardingVersion` / session windows so legacy users re-enter safely.
struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var step = 0
    @State private var showTimePicker = false
    @State private var pickerDate = Date()

    private var profile: UserProfile { appState.userProfile }

    private var isAboutComplete: Bool {
        (!profile.age.isEmpty || !profile.yearOfBirth.isEmpty) && !profile.gender.isEmpty
    }

    private var isTimesComplete: Bool {
        !profile.testTimeCustom.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let medicationUnits = ["pill(s)", "mg", "ml", "patch", "drop(s)"]

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressDots(
                    total: OnboardingFlow.dotCount,
                    current: OnboardingFlow.dot(forWizardStep: step)
                )
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
            if profile.profileComplete && profile.needsOnboardingV2 && step == 0 {
                step = 2
            }
            syncPickerFromProfile()
        }
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack {
                    DatePicker(
                        "Your window",
                        selection: $pickerDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .onChange(of: pickerDate) { newValue in
                        pickerDate = clampWindowTime(newValue)
                    }
                }
                .padding()
                .navigationTitle("Your window")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTimePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            profile.testTimeCustom = formatWindowTime(pickerDate)
                            showTimePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - About you

    private var aboutYouStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About you")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
            Text("This helps us read your tests correctly.")
                .font(.dopax(14.5))
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
                    yearOfBirthPicker

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
                        options: ["Left", "Right", "Both", "Neither"],
                        selection: Binding(
                            get: {
                                ["Left", "Right", "Both", "Neither"].contains(profile.affectedSide)
                                    ? profile.affectedSide : "Left"
                            },
                            set: { profile.affectedSide = $0 }
                        ),
                        fontSize: 12
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

    /// Figma draws year of birth as a select, not a free numeric field. A bounded
    /// list also removes the typo class this study kept hitting (1057, 19577).
    private var birthYearRange: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((thisYear - 110)...(thisYear - 18)).reversed()
    }

    private var yearOfBirthPicker: some View {
        Menu {
            ForEach(birthYearRange, id: \.self) { year in
                Button(String(year)) { setYearOfBirth(String(year)) }
            }
        } label: {
            dropdownLabel(
                text: profile.yearOfBirth.isEmpty ? "Select" : profile.yearOfBirth,
                isPlaceholder: profile.yearOfBirth.isEmpty
            )
        }
    }

    private func setYearOfBirth(_ value: String) {
        profile.yearOfBirth = value
        if let year = Int(value), year > 1900 {
            profile.age = String(Calendar.current.component(.year, from: Date()) - year)
        }
    }

    private var genderPicker: some View {
        Menu {
            ForEach(["Male", "Female", "Non-binary", "Prefer not to say"], id: \.self) { option in
                Button(option) { profile.gender = option }
            }
        } label: {
            dropdownLabel(
                text: profile.gender.isEmpty ? "Select" : profile.gender,
                isPlaceholder: profile.gender.isEmpty
            )
        }
    }

    private func dropdownLabel(text: String, isPlaceholder: Bool) -> some View {
        HStack {
            Text(text)
                .font(.dopax(16))
                .foregroundColor(isPlaceholder ? .dopaxGray50 : .dopaxBlack90)
            Spacer()
            Image(systemName: "chevron.down").foregroundColor(.dopaxGray50)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Medications

    private var medicationsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your medications")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
            Text("So one tap can log a dose later.")
                .font(.dopax(14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(profile.medications.enumerated()), id: \.element.id) { index, _ in
                        medicationRow(at: index)
                    }

                    Button {
                        profile.medications.append(Medication(name: ""))
                    } label: {
                        Text("+ Add another medication")
                            .font(.dopax(15, .medium))
                            .foregroundColor(.onboardingAccent)
                    }
                    .padding(.top, 4)

                    Text("You can always change these in your Profile.")
                        .font(.dopax(13))
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
        .onAppear {
            if profile.medications.isEmpty {
                profile.medications = [Medication(name: "")]
            }
        }
    }

    private func medicationRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingFieldLabel(text: "Medication \(index + 1)")

            OnboardingTextField(
                placeholder: "Levodopa",
                text: Binding(
                    get: { profile.medications[index].name },
                    set: { newValue in
                        profile.medications[index].name = newValue
                    }
                )
            )

            HStack(spacing: 10) {
                medicationUnitPicker(at: index)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0.62)

                OnboardingTextField(
                    placeholder: "1",
                    text: Binding(
                        get: { profile.medications[index].count },
                        set: { newValue in
                            profile.medications[index].count = newValue
                            profile.medications[index].syncDosageFromFields()
                        }
                    ),
                    keyboard: .numberPad
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(0.38)
            }
        }
    }

    private func medicationUnitPicker(at index: Int) -> some View {
        Menu {
            ForEach(medicationUnits, id: \.self) { unit in
                Button(unit) {
                    profile.medications[index].unit = unit
                    profile.medications[index].syncDosageFromFields()
                }
            }
        } label: {
            HStack {
                Text(profile.medications[index].unit)
                    .foregroundColor(.dopaxBlack90)
                Spacer()
                Image(systemName: "chevron.down").foregroundColor(.dopaxGray50)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Test times

    private var testTimesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your three daily sessions")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
            Text("Same times every day teach us fastest.")
                .font(.dopax(14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            VStack(spacing: 12) {
                lockedSessionRow(title: "Morning window", subtitle: profile.testTimeMorning)
                editableWindowRow
                lockedSessionRow(title: "Evening window", subtitle: profile.testTimeEvening)

                Text("A reminder arrives when each window opens. Sessions take about 4 minutes.")
                    .font(.dopax(13))
                    .foregroundColor(.onboardingTextTertiary)
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

    private func lockedSessionRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .foregroundColor(.dopaxGray50)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dopax(15, .semibold))
                    .foregroundColor(.todayTextDisabled)
                Text(subtitle)
                    .font(.dopax(13))
                    .foregroundColor(.dopaxGray50)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .foregroundColor(.dopaxGray50)
                .font(.system(size: 14))
        }
        .padding(16)
        .background(Color.onboardingDotIdle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var editableWindowRow: some View {
        Button {
            syncPickerFromProfile()
            showTimePicker = true
        } label: {
            HStack(spacing: 12) {
                // The design gives the active row the same leading clock as the
                // two locked rows, in accent rather than grey.
                Image(systemName: "clock")
                    .foregroundColor(.onboardingAccent)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your window")
                        .font(.dopax(15, .semibold))
                        .foregroundColor(.dopaxBlack90)
                    HStack(spacing: 0) {
                        Text("Choose a time between ")
                            .font(.dopax(13))
                            .foregroundColor(.onboardingAccent)
                        Text(windowTimeLabel)
                            .font(.dopax(13, .bold))
                            .foregroundColor(.dopaxBlack90)
                    }
                }
                Spacer()
                Circle()
                    .fill(Color.onboardingAccent.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.onboardingAccent)
                    )
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var windowTimeLabel: String {
        let custom = profile.testTimeCustom.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? "12:00-16:00" : custom
    }

    // MARK: - Health apps

    private var healthAppsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect health apps")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
            Text("Activity data helps us see the full picture.")
                .font(.dopax(14.5))
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 8)

            VStack(spacing: 12) {
                googleFitRow
                healthConnectRow(
                    title: "Strava",
                    subtitle: "Workouts",
                    status: profile.healthStravaStatus
                ) {
                    profile.healthStravaStatus = "skipped"
                }
                healthConnectRow(
                    title: "Apple Health",
                    subtitle: "Sleep & activity",
                    status: profile.healthAppleStatus
                ) {
                    requestHealthKit()
                }
            }
            .padding(.top, 28)

            // Figma places "Skip for now" directly under the three cards, not
            // beneath the primary button.
            OnboardingSecondaryLink(title: "Skip for now", color: .onboardingTextTertiary) {
                profile.healthAppleStatus = profile.healthAppleStatus.isEmpty ? "skipped" : profile.healthAppleStatus
                profile.healthStravaStatus = "skipped"
                step = 4
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            Spacer()

            OnboardingPrimaryButton(title: "Continue") { step = 4 }
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private var googleFitRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Fit")
                    .font(.dopax(15, .semibold))
                Text("Steps & activity")
                    .font(.dopax(13))
                    .foregroundColor(.dopaxBlack70)
            }
            Spacer()
            Text("iPhone only")
                .font(.dopax(13, .medium))
                .foregroundColor(.dopaxGray50)
        }
        .padding(16)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func healthConnectRow(
        title: String,
        subtitle: String,
        status: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.dopax(15, .semibold))
                Text(subtitle).font(.dopax(13)).foregroundColor(.dopaxBlack70)
            }
            Spacer()
            Button(status == "connected" ? "Connected" : "Connect", action: action)
                .font(.dopax(14, .semibold))
                .foregroundColor(.onboardingAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.onboardingAccent, lineWidth: 1)
                )
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
                .background(Color.onboardingAccent.opacity(0.15))
                .clipShape(Circle())

            Text("How you use your phone")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            Text("dopa-X reads simple interaction signals, like typing rhythm and scrolling, to notice changes over time.")
                .font(.dopax(15))
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
                .background(Color.onboardingAccent.opacity(0.15))
                .clipShape(Circle())

            Text("Gentle reminders")
                .font(.dopax(26, .bold))
                .foregroundColor(.dopaxBlack90)
                .padding(.top, 28)

            Text("dopa-X will remind you when a session window opens. Nothing else.")
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            OnboardingPrimerCard(
                title: "What we never do",
                bodyText: "No marketing messages. No guilt reminders. Quiet hours are respected."
            )
            .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(title: "Allow reminders") {
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
                .font(.dopax(27, .bold))
                .foregroundColor(.dopaxBlack90)
                .padding(.top, 28)

            Text("For the next 14 days, every session teaches dopa-X how you move. Your 14 days begin with your first completed session, inside its time window.")
                .font(.dopax(15))
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

        FirebaseSyncManager.shared.saveProfileToCloud(profile: profile)
        BackendSyncManager.shared.syncProfile(profile)
    }

    private func syncPickerFromProfile() {
        let trimmed = profile.testTimeCustom.trimmingCharacters(in: .whitespaces)
        if let parsed = parseWindowTime(trimmed) {
            pickerDate = parsed
        } else {
            pickerDate = defaultWindowTime()
        }
    }

    private func parseWindowTime(_ value: String) -> Date? {
        let token = value.split(separator: "-").first.map(String.init) ?? value
        let parts = token.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)
    }

    private func defaultWindowTime() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func clampWindowTime(_ date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        var components = calendar.dateComponents([.year, .month, .day], from: date)

        if hour < 12 {
            components.hour = 12
            components.minute = 0
        } else if hour > 16 || (hour == 16 && minute > 0) {
            components.hour = 16
            components.minute = 0
        } else {
            components.hour = hour
            components.minute = minute
        }
        return calendar.date(from: components) ?? date
    }

    private func formatWindowTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
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
