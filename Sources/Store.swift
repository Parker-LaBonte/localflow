// LocalFlow — data layer: history, lifetime stats, dictionary, and the observable app state the UI binds to.

import Cocoa
import SwiftUI
import AVFoundation
import ApplicationServices
import ServiceManagement

// MARK: - History

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let text: String
    var raw: String? = nil        // what Whisper heard, before cleanup/formatting
    var app: String? = nil        // app it was pasted into
    var bundleID: String? = nil
    var seconds: Double? = nil    // length of the recording
    var model: String? = nil      // formatting model that ran (nil = plain text, no model needed)
    var words: Int { text.split { $0.isWhitespace }.count }
    enum CodingKeys: String, CodingKey { case id, date, text, raw, app, bundleID, seconds, model }
}

extension HistoryItem {
    // Older history.json entries only had date + text.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        text = try c.decode(String.self, forKey: .text)
        raw = try c.decodeIfPresent(String.self, forKey: .raw)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds)
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }
}

enum History {
    static let limit = 500
    static func load() -> [HistoryItem] {
        guard let d = try? Data(contentsOf: Config.historyURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: d)) ?? []
    }
    static func save(_ items: [HistoryItem]) {
        try? JSONEncoder().encode(Array(items.prefix(limit))).write(to: Config.historyURL, options: .atomic)
    }
}

// MARK: - Lifetime stats (kept even when history is off or trimmed)

struct Stats: Codable {
    var words = 0
    var dictations = 0
    var seconds: Double = 0
    var formatted = 0
    var daily: [String: Int] = [:]   // yyyy-MM-dd -> words

    static var url: URL { Config.supportDir.appendingPathComponent("stats.json") }
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static func key(_ d: Date) -> String { dayFmt.string(from: d) }

    static func load() -> Stats {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stats.self, from: d) { return s }
        var s = Stats()   // first run of this version: backfill from history
        for h in History.load() {
            s.add(words: h.words, seconds: h.seconds ?? Double(h.words) / 2.5, formatted: h.model != nil, date: h.date)
        }
        s.save(); return s
    }
    func save() { try? JSONEncoder().encode(self).write(to: Stats.url, options: .atomic) }

    mutating func add(words w: Int, seconds sec: Double, formatted f: Bool, date: Date) {
        words += w; dictations += 1; seconds += sec; if f { formatted += 1 }
        daily[Stats.key(date), default: 0] += w
    }

    var wpm: Int { seconds > 1 ? Int((Double(words) / seconds * 60).rounded()) : 0 }
    /// vs. typing at 40 wpm.
    var minutesSaved: Double { max(0, Double(words) / 40 - seconds / 60) }
    var today: Int { daily[Stats.key(Date())] ?? 0 }
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if (daily[Stats.key(day)] ?? 0) == 0 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while (daily[Stats.key(day)] ?? 0) > 0 { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
    func lastDays(_ n: Int) -> [DayWords] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        return (0..<n).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return DayWords(date: d, words: daily[Stats.key(d)] ?? 0)
        }
    }
}

struct DayWords: Identifiable { let date: Date; let words: Int; var id: Date { date } }

// MARK: - Dictionary (vocabulary.txt)

struct VocabEntry: Identifiable, Hashable {
    var id = UUID()
    var from: String?   // nil = plain term
    var to: String
}

enum VocabStore {
    static func load() -> [VocabEntry] {
        let v = TextCleaner.vocabulary()
        let fixTargets = Set(v.fixes.map(\.1))
        var out = v.fixes.map { VocabEntry(from: $0.0, to: $0.1) }
        var seen = Set<String>()
        for t in v.terms where !fixTargets.contains(t) && seen.insert(t).inserted { out.append(VocabEntry(from: nil, to: t)) }
        return out
    }
    static func save(_ entries: [VocabEntry]) {
        var s = """
        # LocalFlow dictionary. Edit here or in LocalFlow → Dictionary.
        # One word or phrase per line: LocalFlow forces these exact spellings ("github" -> "GitHub").
        # To fix a word Whisper keeps getting wrong, write:  wrong -> right
        # Lines starting with # are ignored.

        """
        for e in entries where e.from == nil { s += e.to + "\n" }
        for e in entries { if let f = e.from { s += "\(f) -> \(e.to)\n" } }
        try? s.write(to: Config.vocabURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - App state

enum Phase: Equatable { case idle, recording, transcribing, formatting }

enum Tab: String, CaseIterable, Identifiable {
    case home, history, dictionary, models, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .models: "cpu"
        case .settings: "gearshape"
        }
    }
}

extension Hotkey {
    var keycap: String { switch self { case .rightOption: "⌥"; case .fn: "fn"; case .rightCommand: "⌘" } }
    var name: String { switch self { case .rightOption: "Right Option"; case .fn: "Fn / Globe"; case .rightCommand: "Right Command" } }
    var detail: String {
        switch self {
        case .rightOption: "Recommended. Rarely used on its own, easy to reach with your thumb."
        case .fn: "The Globe key. Turn off its emoji shortcut in Keyboard settings first."
        case .rightCommand: "Good if you never use the right-hand ⌘ for shortcuts."
        }
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var tab: Tab = .home
    @Published var status = "Starting"
    @Published var engineReady = false     // dictation can work (engine installed)
    @Published var engineLoaded = false    // speech model currently in memory
    @Published var phase: Phase = .idle
    /// Model downloads in progress: ModelFile id → 0…1.
    @Published var downloads: [String: Double] = [:]
    @Published var downloadError: String?
    /// Bumped when a model file is added or removed, so views re-check what's installed.
    @Published var modelsVersion = 0
    @Published var history: [HistoryItem] = History.load()
    @Published var stats = Stats.load()
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled

    @Published var hotkey = Settings.hotkey { didSet { Settings.hotkey = hotkey; onHotkeyChange?() } }
    @Published var smartFormat = Settings.smartFormat {
        didSet {
            Settings.smartFormat = smartFormat
            if smartFormat { if keepLoaded == .always { TextCleaner.warmUp() } } else { TextCleaner.unloadNow() }
        }
    }
    private var autoPicking = false
    /// Selected formatting tier id ("xs", "s", "m", "l").
    @Published var formatTier = Settings.formatTier {
        didSet {
            guard oldValue != formatTier else { return }
            if !autoPicking { Settings.formatTier = formatTier }
            TextCleaner.unloadNow()   // llama-server holds one model; the next dictation starts it with the new one
            if keepLoaded == .always { TextCleaner.warmUp() }
        }
    }
    @Published var sounds = Settings.sounds { didSet { Settings.sounds = sounds } }
    @Published var restoreClipboard = Settings.restoreClipboard { didSet { Settings.restoreClipboard = restoreClipboard } }
    @Published var keepHistory = Settings.keepHistory { didSet { Settings.keepHistory = keepHistory } }
    @Published var livePreview = Settings.livePreview { didSet { Settings.livePreview = livePreview } }
    @Published var keepLoaded = Settings.keepLoaded { didSet { Settings.keepLoaded = keepLoaded; onKeepLoadedChange?() } }

    // Wired up by AppDelegate.
    var onHotkeyChange: (() -> Void)?
    var onKeepLoadedChange: (() -> Void)?
    var restartEngine: () -> Void = {}
    var openWindow: (Tab?) -> Void = { _ in }
    var finishOnboarding: () -> Void = {}

    var currentTier: Tier { Tier.byID(formatTier) ?? Tier.all[0] }
    /// The tier to suggest: the most accurate one that fits this Mac.
    var recommended: Tier { Tier.bestFit }
    var permissionsOK: Bool { axTrusted && micStatus == .authorized }

    func refreshPermissions() {
        let ax = AXIsProcessTrusted(), mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let login = SMAppService.mainApp.status == .enabled
        if ax != axTrusted { axTrusted = ax }
        if mic != micStatus { micStatus = mic }
        if login != loginEnabled { loginEnabled = login }
    }

    func requestMic() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refreshPermissions() } }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        refreshPermissions()
    }

    // MARK: Models

    func download(_ f: ModelFile) { downloadError = nil; Downloader.shared.start(f) }
    func cancelDownload(_ f: ModelFile) { Downloader.shared.cancel(f) }
    func progress(_ f: ModelFile) -> Double? { downloads[f.id] }

    func deleteModel(_ t: Tier) {
        guard let f = t.file else { return }
        if formatTier == t.id { TextCleaner.unloadNow() }
        try? FileManager.default.removeItem(at: f.path)
        if formatTier == t.id { autoPicking = !Settings.userPickedTier; formatTier = Tier.bestInstalled()?.id ?? "xs"; autoPicking = false }
        modelsVersion += 1
    }

    /// Wired to Downloader callbacks by AppDelegate.
    func downloadProgress(_ id: String, _ p: Double?) { downloads[id] = p }
    func downloadFinished(_ id: String, error: String?) {
        modelsVersion += 1
        if let error { downloadError = error; return }
        if id == ModelFile.speech.id { onSpeechModelReady() }
        // A newly downloaded tier becomes the default unless the user chose one themselves.
        if let t = Tier.byID(id), !Settings.userPickedTier, t.accuracy > currentTier.accuracy {
            autoPicking = true; formatTier = t.id; autoPicking = false
        }
    }
    var onSpeechModelReady: () -> Void = {}

    /// First run: fetch the speech model and the best formatting tier for this Mac.
    func downloadEssentials() {
        if !ModelFile.speech.isInstalled { download(.speech) }
        if let f = Tier.bestFit.file, !f.isInstalled { download(f) }
    }
    var essentialsMissing: Bool { !ModelFile.speech.isInstalled }

    func record(_ item: HistoryItem) {
        stats.add(words: item.words, seconds: item.seconds ?? 0, formatted: item.model != nil, date: item.date)
        stats.save()
        guard keepHistory else { return }
        history.insert(item, at: 0)
        if history.count > History.limit { history.removeLast(history.count - History.limit) }
        History.save(history)
    }

    func delete(_ item: HistoryItem) { history.removeAll { $0.id == item.id }; History.save(history) }
    func clearHistory() { history.removeAll(); History.save(history) }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}
