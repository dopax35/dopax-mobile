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

    func upload(fileURL: URL, userId: String, progressHandler: ((Double) -> Void)? = nil) async throws {
        let filename = fileURL.lastPathComponent
        let resumableURL = try await getUploadURL(filename: filename)
        try await uploadFile(fileURL: fileURL, to: resumableURL, progressHandler: progressHandler)
        try await notifyCompletion(userId: userId, filename: filename)
    }

    private func getUploadURL(filename: String) async throws -> URL {
        var req = URLRequest(url: scriptURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["action": "getUploadUrl", "filename": filename, "folderId": folderId]
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

    private func uploadFile(fileURL: URL, to destination: URL, progressHandler: ((Double) -> Void)?) async throws {
        var req = URLRequest(url: destination)
        req.httpMethod = "PUT"
        req.setValue("application/zip", forHTTPHeaderField: "Content-Type")

        let delegate = UploadDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (_, response) = try await session.upload(for: req, fromFile: fileURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UploadError.httpError(http.statusCode)
        }
    }

    private func notifyCompletion(userId: String, filename: String) async throws {
        var req = URLRequest(url: scriptURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["action": "notify", "userId": userId, "filename": filename, "folderId": folderId]
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
