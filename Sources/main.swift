// LocalFlow: private, fully local push-to-talk dictation for macOS.
// Hold the hotkey, talk, release. Whisper (whisper.cpp) transcribes, a small fine-tuned model fixes
// self-corrections and lists, and the text is pasted into whatever app is focused. Nothing leaves this Mac.
//
// This file is the entry point: a few command-line tools for testing, then the menu bar app.

import Cocoa
import ServiceManagement

let args = CommandLine.arguments

/// Runs an async CLI task while keeping the main run loop alive (the engines report back on main).
func runCLI(_ work: @escaping @MainActor () async -> Void) -> Never {
    var done = false
    Task { @MainActor in await work(); done = true }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    exit(0)
}

func secs(_ since: Date) -> String { String(format: "%.2fs", Date().timeIntervalSince(since)) }

switch (args.count, args.count > 1 ? args[1] : "") {

// LocalFlow --selftest file.wav (16 kHz mono 16-bit): a full cold-start dictation through the app's own pipeline.
case (3, "--selftest"):
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else { print("can't read \(args[2])"); exit(1) }
    let samples = d.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Float($0) / 32767 }
    runCLI {
        let t0 = Date()
        Engines.speech.killOrphans(); Engines.format.killOrphans()
        TextCleaner.warmUp()
        guard await Engines.speech.waitUntilReady() else { print("speech engine failed: \(Engines.speech.failed ?? "?")"); return }
        print("speech engine cold start: \(secs(t0))")
        let t1 = Date()
        guard let raw = try? await Engines.transcribe(wav: Recorder.wav(samples), prompt: TextCleaner.vocabularyPrompt()) else {
            print("transcription failed"); Engines.speech.stop(); return
        }
        let clean = TextCleaner.applyVocabulary(TextCleaner.basic(raw))
        print("raw:    \(raw.trimmingCharacters(in: .whitespacesAndNewlines))  [\(secs(t1))]")
        let gated = Settings.smartFormat && TextCleaner.needsSmartFormat(clean, raw: raw)
        let out = gated ? await TextCleaner.smartFormat(clean) : clean
        print("output: \(out.debugDescription)  [\(gated ? Settings.formatTier.uppercased() : "no model"), \(secs(t1)) after audio]")
        Engines.speech.stop(); TextCleaner.unloadNow()
    }

// LocalFlow --formattest "raw transcript": cleanup + gate + smart format on text.
case (3, "--formattest"):
    runCLI {
        let t0 = Date()
        let clean = TextCleaner.applyVocabulary(TextCleaner.basic(args[2]))
        let gated = TextCleaner.needsSmartFormat(clean, raw: args[2])
        let out = gated ? await TextCleaner.smartFormat(clean) : clean
        print("[\(gated ? Settings.formatTier.uppercased() : "skip") \(secs(t0))] \(out.debugDescription)")
        TextCleaner.unloadNow()
    }

// LocalFlow --xs "text" …: XS tier output (parity testing against train/tagger.py).
case (3..., "--xs"):
    for t in args.dropFirst(2) { print((XSTagger.shared.format(t) ?? "<XS unavailable>").debugDescription) }
    exit(0)

// LocalFlow --gate "text": prints 1 if the smart-format gate would run the model (used by train/eval3.py).
case (3, "--gate"):
    print(TextCleaner.needsSmartFormat(TextCleaner.basic(args[2]), raw: args[2]) ? "1" : "0"); exit(0)

// LocalFlow --download speech|s|m|l: fetch and verify a model with the app's own downloader.
case (3, "--download"):
    let all = [ModelFile.speech, .small, .medium, .large]
    guard let f = all.first(where: { $0.id == args[2] }) else { print("unknown model \(args[2])"); exit(1) }
    if f.isInstalled { print("\(f.filename) is already installed"); exit(0) }
    runCLI {
        let t0 = Date()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var last = -1
            Downloader.shared.onProgress = { _, p in
                if let p, Int(p * 10) != last { last = Int(p * 10); print("  \(Int(p * 100))%") }
            }
            Downloader.shared.onFinished = { _, err in print(err.map { "failed: \($0)" } ?? "ok: \(f.path.path)"); c.resume() }
            Downloader.shared.start(f)
        }
        print("took \(secs(t0))")
    }

// LocalFlow --login on|off: toggle Open at Login.
case (3, "--login"):
    do { if args[2] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
    catch { print("error: \(error.localizedDescription)") }
    print("open at login: \(SMAppService.mainApp.status == .enabled ? "on" : "off")"); exit(0)

// LocalFlow --snapshot <dir>: render every page (light + dark) and the HUD offscreen to PNGs.
case (3, "--snapshot"):
    runSnapshots(args[2]); exit(0)

default:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
