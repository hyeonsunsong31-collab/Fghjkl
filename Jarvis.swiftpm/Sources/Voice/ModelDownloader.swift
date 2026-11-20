import Foundation

/// Downloads model files (Hugging Face repos, GitHub raw files) with byte-level
/// progress. Used once for Kokoro and the optional Deep-Think model; after that
/// Jarvis is fully offline.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Item: Hashable {
        let url: URL
        let relativePath: String
        let size: Int64
    }

    enum DownloadError: LocalizedError {
        case badResponse(String), listingFailed(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(let s): return "Download failed: \(s)"
            case .listingFailed(let s): return "Could not list model files: \(s)"
            }
        }
    }

    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var currentExpected: Int64 = 0
    private var onBytes: ((Int64) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// List files of a Hugging Face model repository.
    static func huggingFaceFiles(repo: String, revision: String = "main", include: (String) -> Bool) async throws -> [Item] {
        guard let api = URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)?recursive=1") else { return [] }
        let (data, response) = try await URLSession.shared.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DownloadError.listingFailed(repo)
        }
        return entries.compactMap { e in
            guard (e["type"] as? String) == "file", let path = e["path"] as? String, include(path) else { return nil }
            let size = (e["size"] as? NSNumber)?.int64Value ?? 0
            let encoded = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
            guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(encoded)") else { return nil }
            return Item(url: url, relativePath: path, size: size)
        }
    }

    /// Download all items into `directory`, reporting overall progress 0…1.
    func download(_ items: [Item], to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let total = max(1, items.reduce(Int64(0)) { $0 + max($1.size, 1) })
        var done: Int64 = 0
        for item in items {
            let destination = directory.appendingPathComponent(item.relativePath)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let size = attrs[.size] as? NSNumber, item.size > 0, size.int64Value == item.size {
                done += item.size
                progress(Double(done) / Double(total))
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = done
            onBytes = { written in progress(Double(base + written) / Double(total)) }
            let temp = try await downloadOne(item.url)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temp, to: destination)
            done += max(item.size, 1)
            progress(Double(done) / Double(total))
        }
        onBytes = nil
    }

    private func downloadOne(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            continuation?.resume(throwing: DownloadError.badResponse("HTTP \(status) for \(downloadTask.originalRequest?.url?.lastPathComponent ?? "")"))
            continuation = nil
            return
        }
        // The temporary file is deleted when this method returns: move it now.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: keep)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onBytes?(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
