// LocalFlow: the model catalog (speech + formatting tiers) and the in-app downloader.

import Foundation
import CryptoKit

// MARK: - Downloadable model files

struct ModelFile: Equatable {
    let id: String
    let filename: String
    let url: URL
    let bytes: Int64
    let sha256: String

    var path: URL { Config.modelsDir.appendingPathComponent(filename) }
    var installedPath: String? { FileManager.default.fileExists(atPath: path.path) ? path.path : nil }
    var isInstalled: Bool { installedPath != nil }

    /// Where the formatting models are published (GitHub release assets of this repo).
    static let releaseBase = "https://github.com/Parker-LaBonte/localflow/releases/download/models-v1/"

    /// Whisper Large v3 Turbo (q5_0), straight from the whisper.cpp model repo.
    static let speech = ModelFile(
        id: "speech", filename: "ggml-large-v3-turbo-q5_0.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
        bytes: 574_041_195, sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")

    static let small = ModelFile(
        id: "s", filename: "localflow-s.gguf", url: URL(string: releaseBase + "localflow-s.gguf")!,
        bytes: 319_211_008, sha256: "2af38d0f6e023831eca980ff5c9b272449596af827f018bb65129f5e5fff0c92")
    static let medium = ModelFile(
        id: "m", filename: "localflow-m.gguf", url: URL(string: releaseBase + "localflow-m.gguf")!,
        bytes: 883_016_416, sha256: "017caedc822feda3b22d6060b99d827da90154bf4a3aefa7d8d461f9a7a2e6f6")
    static let large = ModelFile(
        id: "l", filename: "localflow-l.gguf", url: URL(string: releaseBase + "localflow-l.gguf")!,
        bytes: 1_793_550_176, sha256: "76c9d8fc77e77bcdbb3d3636df9b2e9fc530c48142d0f2d8f87e6da6449a1974")

    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

// MARK: - Formatting tiers

struct Tier: Identifiable {
    let id: String, title: String, name: String
    let file: ModelFile?        // nil = XS, bundled inside the app
    let sizeMB: Int, ramMB: Int, accuracy: Int, speed: String, speedScore: Double, blurb: String

    var sizeLabel: String { sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB" }
    var ramLabel: String { ramMB >= 1000 ? String(format: "%.1f GB", Double(ramMB) / 1000) : "\(ramMB) MB" }
    /// Fits if it uses at most 15% of RAM (leaves room for everything else you run).
    var fits: Bool { Double(ramMB) <= Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576 * 0.15 }
    var isInstalled: Bool { file?.isInstalled ?? XSTagger.shared.available }

    /// Held-out test sentences the accuracy numbers are out of (train/test_set3.py + test_set4.py, app pipeline).
    static let testCases = 265
    // Accuracy and median latency measured by train/eval3.py through the app's own gate (M4, 24 GB).
    static let all: [Tier] = [
        Tier(id: "xs", title: "XS", name: "Extra Small", file: nil, sizeMB: 26, ramMB: 60, accuracy: 230, speed: "2 ms", speedScore: 1,
             blurb: "Tiny English-only word tagger (Core ML). Can only keep, delete and structure your own words, so it never invents text. Built in."),
        Tier(id: "s", title: "S", name: "Small", file: .small, sizeMB: 319, ramMB: 380, accuracy: 240, speed: "0.14 s", speedScore: 0.85,
             blurb: "Qwen2.5-0.5B fine-tuned for dictation, English-only vocabulary."),
        Tier(id: "m", title: "M", name: "Medium", file: .medium, sizeMB: 883, ramMB: 1000, accuracy: 255, speed: "0.25 s", speedScore: 0.7,
             blurb: "Qwen2.5-1.5B fine-tuned for dictation, English-only vocabulary. Best accuracy per MB."),
        Tier(id: "l", title: "L", name: "Large", file: .large, sizeMB: 1794, ramMB: 2000, accuracy: 262, speed: "0.43 s", speedScore: 0.5,
             blurb: "Qwen2.5-3B fine-tuned for dictation, English-only vocabulary. The most accurate. Non-commercial license (Qwen Research)."),
    ]
    static func byID(_ id: String) -> Tier? { all.first { $0.id == id } }

    /// Most accurate tier that fits this Mac's memory (what onboarding downloads).
    static var bestFit: Tier { all.filter(\.fits).max { $0.accuracy < $1.accuracy } ?? all[0] }
    /// Most accurate tier that is downloaded and fits.
    static func bestInstalled() -> Tier? { all.filter { $0.isInstalled && $0.fits }.max { $0.accuracy < $1.accuracy } }
}

// MARK: - Downloader

/// Downloads model files into ~/Library/Application Support/LocalFlow/models, verifying size and SHA-256.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    static let shared = Downloader()
    /// id → progress 0…1 (main thread).
    var onProgress: ((String, Double?) -> Void)?
    var onFinished: ((String, String?) -> Void)?   // id, error message

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var tasks: [Int: ModelFile] = [:]
    private let lock = NSLock()

    func isDownloading(_ f: ModelFile) -> Bool { lock.lock(); defer { lock.unlock() }; return tasks.values.contains(f) }

    func start(_ f: ModelFile) {
        guard !f.isInstalled, !isDownloading(f) else { return }
        let t = session.downloadTask(with: f.url)
        lock.lock(); tasks[t.taskIdentifier] = f; lock.unlock()
        report(f.id, 0)
        t.resume()
    }

    func cancel(_ f: ModelFile) {
        session.getAllTasks { all in
            self.lock.lock()
            let ids = self.tasks.filter { $0.value == f }.map(\.key)
            self.lock.unlock()
            all.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() }
        }
    }

    private func report(_ id: String, _ p: Double?) { DispatchQueue.main.async { self.onProgress?(id, p) } }
    private func file(_ t: URLSessionTask) -> ModelFile? { lock.lock(); defer { lock.unlock() }; return tasks[t.taskIdentifier] }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite _: Int64) {
        guard let f = file(t) else { return }
        report(f.id, min(0.99, Double(w) / Double(f.bytes)))
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo tmp: URL) {
        guard let f = file(t) else { return }
        // The temp file is deleted when this returns: move it first, verify after.
        let staged = Config.modelsDir.appendingPathComponent(f.filename + ".part")
        try? FileManager.default.removeItem(at: staged)
        do { try FileManager.default.moveItem(at: tmp, to: staged) } catch { done(t, f, "Couldn't save the file"); return }
        let status = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { try? FileManager.default.removeItem(at: staged); done(t, f, "Server returned \(status)"); return }
        guard Downloader.sha256(of: staged) == f.sha256 else {
            try? FileManager.default.removeItem(at: staged); done(t, f, "Download was corrupted, try again"); return
        }
        try? FileManager.default.removeItem(at: f.path)
        do { try FileManager.default.moveItem(at: staged, to: f.path); done(t, f, nil) } catch { done(t, f, "Couldn't save the file") }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        guard let e, let f = file(t) else { return }
        done(t, f, (e as NSError).code == NSURLErrorCancelled ? nil : e.localizedDescription)
    }

    private func done(_ t: URLSessionTask, _ f: ModelFile, _ err: String?) {
        lock.lock(); let was = tasks.removeValue(forKey: t.taskIdentifier) != nil; lock.unlock()
        guard was else { return }
        report(f.id, nil)
        DispatchQueue.main.async { self.onFinished?(f.id, err) }
    }

    /// Streaming SHA-256 (models are up to 1.8 GB; never load them whole).
    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
