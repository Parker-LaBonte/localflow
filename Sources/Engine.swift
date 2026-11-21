// LocalFlow: configuration, settings, and the two local inference servers (speech + formatting).
// Both run as child processes bound to 127.0.0.1, start when you press the hotkey, and stop again
// after a short idle period, so an idle LocalFlow uses almost no memory.

import Cocoa

// MARK: - Paths

enum Config {
    static let speechPort = 8178
    static let formatPort = 8179

    static let supportDir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let modelsDir: URL = {
        let u = supportDir.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static var vocabURL: URL { supportDir.appendingPathComponent("vocabulary.txt") }
    static var historyURL: URL { supportDir.appendingPathComponent("history.json") }
    static var logURL: URL { supportDir.appendingPathComponent("engine.log") }

    /// A bundled helper (LocalFlow.app/Contents/Helpers), or a Homebrew install when running a dev build without one.
    static func helper(_ name: String) -> String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)").path
        return [bundled, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Settings

enum Hotkey: String, CaseIterable {
    case rightOption, fn, rightCommand
    var keyCode: UInt16 { switch self { case .rightOption: 61; case .fn: 63; case .rightCommand: 54 } }
    var flag: NSEvent.ModifierFlags { switch self { case .rightOption: .option; case .fn: .function; case .rightCommand: .command } }
    var label: String { switch self { case .rightOption: "Right Option ⌥"; case .fn: "Fn / Globe 🌐"; case .rightCommand: "Right Command ⌘" } }
}

/// How long the speech and formatting models stay in memory after a dictation.
enum KeepLoaded: Int, CaseIterable, Identifiable {
    case dictation = 15, fiveMinutes = 300, oneHour = 3600, always = -1
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .dictation: "Only while dictating"
        case .fiveMinutes: "5 minutes"
        case .oneHour: "1 hour"
        case .always: "Always"
        }
    }
    var detail: String {
        switch self {
        case .dictation: "Models load when you press the key (while you talk) and unload 15 s after you finish. Almost no memory when idle."
        case .fiveMinutes, .oneHour: "Models stay loaded for a while after each dictation, then unload."
        case .always: "Models stay in memory all the time. Uses the most memory."
        }
    }
}

enum Settings {
    static let d = UserDefaults.standard
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }

    static var hotkey: Hotkey {
        get { Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }
    static var smartFormat: Bool { get { bool("smartFormat", true) } set { d.set(newValue, forKey: "smartFormat") } }
    /// Tier id ("xs", "s", "m", "l"). Until the user picks one: the best tier that is downloaded and fits this Mac.
    static var formatTier: String {
        get {
            if let t = d.string(forKey: "formatTier"), Tier.byID(t) != nil { return t }
            return Tier.bestInstalled()?.id ?? "xs"
        }
        set { d.set(newValue, forKey: "formatTier") }
    }
    static var userPickedTier: Bool { d.string(forKey: "formatTier") != nil }
    static var sounds: Bool { get { bool("sounds", true) } set { d.set(newValue, forKey: "sounds") } }
    static var livePreview: Bool { get { bool("livePreview", true) } set { d.set(newValue, forKey: "livePreview") } }
    static var keepHistory: Bool { get { bool("keepHistory", true) } set { d.set(newValue, forKey: "keepHistory") } }
    static var restoreClipboard: Bool { get { bool("restoreClipboard", true) } set { d.set(newValue, forKey: "restoreClipboard") } }
    static var keepLoaded: KeepLoaded {
        get { KeepLoaded(rawValue: d.integer(forKey: "keepLoaded")) ?? .dictation }
        set { d.set(newValue.rawValue, forKey: "keepLoaded") }
    }
}

// MARK: - On-demand server process

/// A local HTTP inference server (whisper-server or llama-server) that is started on demand and stopped when idle.
/// All state is touched on the main thread.
final class EngineProcess {
    let name: String
    let port: Int
    private let healthPath: String
    /// Command-line arguments, or nil when the model file isn't there.
    private let arguments: () -> [String]?

    private var process: Process?
    private var idleStop: DispatchWorkItem?
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private(set) var ready = false
    private(set) var failed: String?
    var onLoaded: ((Bool) -> Void)?

    init(name: String, port: Int, healthPath: String, arguments: @escaping () -> [String]?) {
        self.name = name; self.port = port; self.healthPath = healthPath; self.arguments = arguments
    }

    var binary: String? { Config.helper(name) }
    var running: Bool { process != nil }

    /// Kill a server left behind by a previous crash that still holds our port.
    func killOrphans() {
        let k = Process(); k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-f", "\(name).*--port \(port)"]
        try? k.run(); k.waitUntilExit()
    }

    /// Starts the server if needed and cancels any pending idle shutdown.
    func wake() {
        idleStop?.cancel(); idleStop = nil
        guard process == nil else { return }
        guard let bin = binary else { fail("\(name) is missing"); return }
        guard let args = arguments() else { fail("Model not downloaded"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args + ["--host", "127.0.0.1", "--port", "\(port)"]
        // ggml only auto-discovers the CPU plugin next to a relocated binary; point it at the bundled Metal (GPU) one.
        let metal = URL(fileURLWithPath: bin).deletingLastPathComponent().appendingPathComponent("libggml-metal.so").path
        if FileManager.default.fileExists(atPath: metal) {
            p.environment = ProcessInfo.processInfo.environment.merging(["GGML_BACKEND_PATH": metal]) { $1 }
        }
        if let fh = FileHandle(forWritingAtPath: Config.logURL.path) ?? {
            FileManager.default.createFile(atPath: Config.logURL.path, contents: nil)
            return FileHandle(forWritingAtPath: Config.logURL.path)
        }() {
            fh.seekToEndOfFile(); p.standardOutput = fh; p.standardError = fh
        }
        p.terminationHandler = { [weak self] dead in
            DispatchQueue.main.async {
                guard let self, self.process === dead else { return }   // stopped on purpose
                self.process = nil; self.setReady(false); self.resume(false)   // crashed: the next dictation restarts it
            }
        }
        do { try p.run() } catch { fail("Couldn't launch \(name)"); return }
        process = p; failed = nil
        setReady(false)
        poll(p, attempt: 0)
    }

    private func fail(_ msg: String) { failed = msg; resume(false) }
    private func setReady(_ r: Bool) { if ready != r { ready = r; onLoaded?(r) } }
    private func resume(_ ok: Bool) { let w = waiters; waiters = []; w.forEach { $0.resume(returning: ok) } }

    private func poll(_ p: Process, attempt: Int) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(healthPath)")!)
        req.timeoutInterval = 1
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                if (resp as? HTTPURLResponse)?.statusCode == 200 {
                    self.setReady(true); self.resume(true)
                } else if attempt < 1200 {   // up to 60 s, checking every 50 ms
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.poll(p, attempt: attempt + 1) }
                } else {
                    self.fail("\(self.name) didn't start (see log)"); self.stop()
                }
            }
        }.resume()
    }

    /// Waits until the server answers, starting it if needed. False if it can't start.
    @MainActor func waitUntilReady() async -> Bool {
        wake()
        if ready { return true }
        if process == nil { return false }
        return await withCheckedContinuation { waiters.append($0) }
    }

    /// Stop after `seconds` without use. Negative = keep running.
    func scheduleSleep(after seconds: Int) {
        idleStop?.cancel(); idleStop = nil
        guard seconds >= 0, process != nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.stop() }
        idleStop = w
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: w)
    }

    func stop() {
        idleStop?.cancel(); idleStop = nil
        let p = process; process = nil
        setReady(false); resume(false)
        p?.terminate()
    }

    func post(_ path: String, body: Data, contentType: String, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        return try await URLSession.shared.upload(for: req, from: body).0
    }
}

// MARK: - The two engines

enum Engines {
    /// whisper.cpp server with Whisper Large v3 Turbo.
    static let speech = EngineProcess(name: "whisper-server", port: Config.speechPort, healthPath: "/") {
        guard let model = ModelFile.speech.installedPath else { return nil }
        return ["-m", model, "-t", "\(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))"]
    }

    /// llama.cpp server with the selected formatting tier (S, M or L). XS runs in-process (Core ML) instead.
    static let format = EngineProcess(name: "llama-server", port: Config.formatPort, healthPath: "/health") {
        guard let tier = Tier.byID(Settings.formatTier), let path = tier.file?.installedPath else { return nil }
        return ["-m", path, "-c", "2048", "-ngl", "99", "-np", "1", "--no-warmup"]
    }

    static func transcribe(wav: Data, prompt: String?) async throws -> String {
        let boundary = "LF-\(UUID().uuidString)"
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav); add("\r\n")
        field("response_format", "json")
        field("temperature", "0.0")
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }
        add("--\(boundary)--\r\n")
        let data = try await speech.post("/inference", body: body, contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
        struct R: Decodable { let text: String?; let error: String? }
        let r = try JSONDecoder().decode(R.self, from: data)
        if let e = r.error { throw NSError(domain: "whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: e]) }
        return r.text ?? ""
    }

    /// One chat turn with the fine-tuned formatter (ChatML, greedy).
    static func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let prompt = "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        let body: [String: Any] = ["prompt": prompt, "temperature": 0, "n_predict": maxTokens, "cache_prompt": true,
                                   "stop": ["<|im_end|>", "<|endoftext|>"]]
        let data = try await format.post("/completion", body: try JSONSerialization.data(withJSONObject: body),
                                         contentType: "application/json", timeout: 15)
        struct R: Decodable { let content: String }
        return try JSONDecoder().decode(R.self, from: data).content
    }
}
