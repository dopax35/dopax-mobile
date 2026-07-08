import SwiftUI

struct DataExportView: View {
    @EnvironmentObject var appState: AppState
    @State private var dates: [String] = []
    @State private var uploadingDate: String?
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String?
    @State private var showDeleteAlert = false
    @State private var dateToDelete: String?
    @State private var shareItem: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if dates.isEmpty {
                    EmptyStateView(
                        title: "No logs found",
                        systemImage: "doc.text.magnifyingglass",
                        descriptionText: "There are no test result files in the current user directory."
                    )
                } else {
                    List {
                        ForEach(dates, id: \.self) { date in
                            dateRow(date)
                        }
                    }
                }
            }
            .navigationTitle("My Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: exportHealthKit) {
                        Label("Export HealthKit", systemImage: "heart.text.square")
                    }
                }
            }
            .onAppear { reload() }
            .alert("Delete Data?", isPresented: $showDeleteAlert, presenting: dateToDelete) { date in
                Button("Delete", role: .destructive) {
                    appState.dataManager.deleteDate(date)
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: { date in
                Text("All data for \(date) will be permanently deleted.")
            }
            .alert("Upload Error", isPresented: .init(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadError ?? "")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareItem {
                    ShareSheet(url: url)
                }
            }
        }
    }

    @ViewBuilder
    private func dateRow(_ date: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(date))
                        .fontWeight(.medium)
                    Text("\(appState.dataManager.fileCount(for: date)) files · \(appState.dataManager.sizeString(for: date))")
                        .font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                if appState.dataManager.isUploaded(date) {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundColor(.dopaxStatusSuccess)
                }
            }

            if uploadingDate == date {
                ProgressView(value: uploadProgress)
                    .tint(.dopaxBlue)
                    .padding(.top, 4)
            } else {
                HStack(spacing: 12) {
                    Button(action: { shareDate(date) }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { uploadDate(date) }) {
                        Label("Upload", systemImage: "icloud.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.dopaxBlue)

                    Spacer()

                    Button(role: .destructive, action: {
                        dateToDelete = date
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func reload() {
        dates = appState.dataManager.listDates()
    }

    private func shareDate(_ date: String) {
        guard let url = try? appState.dataManager.zipDate(date) else { return }
        shareItem = url
        showShareSheet = true
    }

    private func uploadDate(_ date: String) {
        guard let zipURL = try? appState.dataManager.zipDate(date) else { return }
        uploadingDate = date
        uploadProgress = 0

        Task {
            do {
                let uploader = CloudUploader()
                try await uploader.upload(
                    zipURL: zipURL,
                    userId: appState.userProfile.userId,
                    dateStr: date,
                    progressHandler: { p in
                        DispatchQueue.main.async { uploadProgress = p }
                    }
                )
                try? FileManager.default.removeItem(at: zipURL)
                await MainActor.run {
                    appState.dataManager.markUploaded(date)
                    uploadingDate = nil
                    reload()
                }
            } catch {
                await MainActor.run {
                    uploadingDate = nil
                    uploadError = error.localizedDescription
                }
            }
        }
    }

    private func exportHealthKit() {
        Task {
            let metrics = await appState.healthKitManager.fetchGaitMetrics(days: 90)
            let csv = appState.healthKitManager.csvString(for: metrics)
            appState.dataManager.writeGaitMetrics(csvString: csv)
        }
    }

    private func formattedDate(_ dateKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateKey) else { return dateKey }
        let g = DateFormatter(); g.dateStyle = .long
        return g.string(from: d)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
