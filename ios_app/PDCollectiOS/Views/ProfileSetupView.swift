import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var newMedName = ""
    @State private var newMedDosage = ""
    @State private var editingMedication: Medication?

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
                        .keyboardType(.numbersAndPunctuation)
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
                    ForEach(profile.medications) { med in
                        Button {
                            editingMedication = med
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(med.name).foregroundColor(.primary)
                                    if !med.dosage.isEmpty {
                                        Text(med.dosage).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundColor(.blue)
                            }
                        }
                    }
                    .onDelete { idx in
                        var meds = profile.medications
                        meds.remove(atOffsets: idx)
                        profile.medications = meds
                    }

                    Button("Add Medication") {
                        let newMed = Medication(name: "", dosage: "")
                        editingMedication = newMed
                    }
                }
                
                Section("Keystroke Logging") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To collect typing patterns (not what you type, just how you type), please enable the PDCollect keyboard.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Button("Go to Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                        
                        Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → PDCollectKeyboard")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Your Profile")
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Dismiss") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if profile.gender.isEmpty { profile.gender = "Prefer not to say" }
                        profile.profileComplete = true
                        FirebaseSyncManager.shared.saveProfileToCloud(profile: profile)
                    }
                    .disabled(!isComplete)
                }
            }
            .sheet(item: $editingMedication) { med in
                MedicationEditSheet(medication: med, profile: profile)
            }
        }
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
