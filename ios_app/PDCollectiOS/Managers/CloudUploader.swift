import Foundation

enum UploadError: LocalizedError {
    case noUploadURL
    case httpError(Int)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .noUploadURL:       return "Failed to get upload URL from server."
        case .httpError(let c): return "HTTP error \(c)"
        case .unknown(let e):   return e.localizedDescription
        }
    }
}

struct CloudUploader {
    private let scriptURL = URL(string: Constants.googleAppsScriptURL)!
    private let folderId  = Constants.driveFolderId

    /// Upload a ZIP file to Google Drive via the dopa-X Apps Script.
    /// Filename format: `PDData_{userId}_{date}_iOS.zip` to distinguish from Android.
    func upload(zipURL: URL, userId: String, dateStr: String,
                progressHandler: ((Double) -> Void)? = nil) async throws {
        let filename = Self.cloudFilename(userId: userId, dateStr: dateStr)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int) ?? 0
        let sessionId = Self.uploadSessionId(userId: userId, dateStr: dateStr, bytes: fileSize)

        let resumableURL = try await getUploadURL(
            filename: filename, fileSize: fileSize, sessionId: sessionId)
        try await uploadFile(fileURL: zipURL, to: resumableURL, progressHandler: progressHandler)
        try await notifyCompletion(
            userId: userId, filename: filename, fileSize: fileSize, sessionId: sessionId)
    }

    // MARK: - Naming (matches Android + _iOS suffix)

    static func cloudFilename(userId: String, dateStr: String) -> String {
        "PDData_\(userId)_\(dateStr)_iOS.zip"
    }

    static func uploadSessionId(userId: String, dateStr: String, bytes: Int) -> String {
        let safeUser = userId.isEmpty ? "unknown" : userId.replacingOccurrences(
            of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return "\(safeUser)-\(dateStr)-\(bytes)"
    }

    // MARK: - Steps

    private func getUploadURL(filename: String, fileSize: Int, sessionId: String) async throws -> URL {
        var req = URLRequest(url: scriptURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "action": "getUploadUrl",
            "filename": filename,
            "folderId": folderId,
            "mimeType": "application/zip",
            "contentLength": fileSize,
            "uploadSessionId": sessionId,
            "replaceExisting": true
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UploadError.httpError(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlStr = json["uploadUrl"] as? String,
              let url = URL(string: urlStr) else {
            throw UploadError.noUploadURL
        }
        return url
    }

    private func uploadFile(fileURL: URL, to destination: URL,
                            progressHandler: ((Double) -> Void)?) async throws {
        var req = URLRequest(url: destination)
        req.httpMethod = "PUT"
        req.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600

        let delegate = UploadDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        // A delegate-backed URLSession keeps a strong reference to its
        // delegate until explicitly invalidated — it does NOT get released
        // just because `session` goes out of scope. A new session is created
        // per upload call, so without this the app leaked one session +
        // delegate per uploaded date for the rest of the process's life.
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.upload(for: req, fromFile: fileURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UploadError.httpError(http.statusCode)
        }
    }

    private func notifyCompletion(userId: String, filename: String,
                                  fileSize: Int, sessionId: String) async throws {
        var req = URLRequest(url: scriptURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "action": "notify",
            "userId": userId,
            "filename": filename,
            "folderId": folderId,
            "contentLength": fileSize,
            "uploadSessionId": sessionId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }
}

private class UploadDelegate: NSObject, URLSessionTaskDelegate {
    let progressHandler: ((Double) -> Void)?
    init(progressHandler: ((Double) -> Void)?) { self.progressHandler = progressHandler }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progressHandler?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
