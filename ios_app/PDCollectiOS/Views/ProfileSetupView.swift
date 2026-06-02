import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var newMed = ""

    private var profile: UserProfile { appState.userProfile }

    private var isComplete: Bool {
        !profile.age.isEmpty && !profile.gender.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Participant ID") {
                    HStack {
                        Text(profile.userId)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Auto-generated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Demographics") {
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Years", text: Binding(
                            get: { profile.age },
                            set: { profile.age = $0 }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    }

                    Picker("Gender", selection: Binding(
                        get: { profile.gender.isEmpty ? "Prefer not to say" : profile.gender },
                        set: { profile.gender = $0 }
                    )) {
                        ForEach(["Male", "Female", "Non-binary", "Prefer not to say"], id: \.self) { Text($0) }
                    }

                    Picker("Dominant Hand", selection: Binding(
                        get: { profile.dominantHand },
                        set: { profile.dominantHand = $0 }
                    )) {
                        ForEach(["Right", "Left"], id: \.self) { Text($0) }
                    }

                    Picker("PD Affected Side", selection: Binding(
                        get: { profile.affectedSide },
                        set: { profile.affectedSide = $0 }
                    )) {
                        ForEach(["Left", "Right", "Both", "None / Unknown"], id: \.self) { Text($0) }
                    }
                }

                Section("Current Medications") {
                    ForEach(profile.medications, id: \.self) { med in
                        Text(med)
                    }
                    .onDelete { idx in
                        var meds = profile.medications
                        meds.remove(atOffsets: idx)
                        profile.medications = meds
                    }

                    HStack {
                        TextField("Add medication…", text: $newMed)
                        Button("Add") {
                            let trimmed = newMed.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            profile.medications.append(trimmed)
                            newMed = ""
                        }
                        .disabled(newMed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Your Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if profile.gender.isEmpty { profile.gender = "Prefer not to say" }
                        profile.profileComplete = true
                    }
                    .disabled(!isComplete)
                }
            }
        }
    }
}
