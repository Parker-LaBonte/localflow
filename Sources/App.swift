// LocalFlow — app controller: hotkey handling, record → transcribe → format → paste, menu bar, windows.

import Cocoa
import SwiftUI
import AVFoundation
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let speech = Engines.speech
    private let recorder = Recorder()
    private let hud = HUD()
    private let model = AppModel.shared
    private var monitors: [Any] = []

    private enum Mode { case idle, holding(Date), handsFree, busy }
    private var mode: Mode = .idle
    private var keyIsDown = false
    private var targetApp: NSRunningApplication?
    private var mainWindow: NSWindow?
    private var previewTask: Task<Void, Never>?
    private var session = 0
    private var onboardingWindow: NSWindow?
    private var onboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("waveform")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu

        seedVocabulary()
        trimLog()
        Engines.speech.killOrphans(); Engines.format.killOrphans()
        speech.onLoaded = { [weak self] l in self?.model.engineLoaded = l }
        Downloader.shared.onProgress = { [weak self] id, p in self?.model.downloadProgress(id, p) }
        Downloader.shared.onFinished = { [weak self] id, err in self?.model.downloadFinished(id, error: err) }
        model.onSpeechModelReady = { [weak self] in self?.refreshEngineStatus(); self?.applyKeepLoaded() }
        refreshEngineStatus()
        recorder.onLevel = { [weak self] l in DispatchQueue.main.async { self?.hud.model.push(l) } }

        model.restartEngine = { [weak self] in Engines.speech.stop(); TextCleaner.unloadNow(); self?.applyKeepLoaded() }
        model.onKeepLoadedChange = { [weak self] in self?.applyKeepLoaded() }
        model.openWindow = { [weak self] tab in self?.showMain(tab) }
        model.onHotkeyChange = { [weak self] in self?.keyIsDown = false }
        model.finishOnboarding = { [weak self] in
            guard let self else { return }
            self.onboarded = true
            self.onboardingWindow?.close()
            self.showMain(.home)
        }

        installMonitors()
        applyKeepLoaded()
        primeEnginesIfNeeded()

        if onboarded {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.model.refreshPermissions() } }
            if !AXIsProcessTrusted() { model.requestAccessibility() }
        } else {
            showOnboarding()
        }
        // Speech model + best formatting tier, in the background (also resumes after a quit mid-download).
        if model.essentialsMissing { model.downloadEssentials() }
    }

    func applicationWillTerminate(_ n: Notification) { Engines.speech.stop(); Engines.format.stop() }

    private func refreshEngineStatus() {
        let ok = speech.binary != nil && ModelFile.speech.isInstalled
        model.engineReady = ok
        model.status = ok ? "Ready" : speech.binary == nil ? "Speech engine missing" : "Speech model not downloaded"
    }

    // MARK: Memory

    /// "Always": load everything now and keep it. Otherwise models only load while dictating.
    private func applyKeepLoaded() {
        if Settings.keepLoaded == .always { if model.engineReady { speech.wake() }; TextCleaner.warmUp() } else { sleepModels() }
    }

    /// First launch after an install or update: start both engines once in the background, so one-time costs
    /// (macOS checking the new binaries, Metal compiling GPU shaders) don't land on your first dictation.
    private func primeEnginesIfNeeded() {
        let exe = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let stamp = "\(exe?.timeIntervalSince1970 ?? 0)"
        guard UserDefaults.standard.string(forKey: "primedBuild") != stamp, model.engineReady else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.model.phase == .idle else { return }
            Task { @MainActor in
                async let a = self.speech.waitUntilReady()
                async let b: Bool = Settings.formatTier == "xs" ? true : Engines.format.waitUntilReady()
                if await a, await b { UserDefaults.standard.set(stamp, forKey: "primedBuild") }
                if self.model.phase == .idle { self.sleepModels() }
            }
        }
    }

    /// After a dictation: let the speech engine and formatting model unload after the KeepLoaded grace period.
    private func sleepModels() {
        speech.scheduleSleep(after: Settings.keepLoaded.rawValue)
        TextCleaner.release()
    }

    func applicationDidBecomeActive(_ n: Notification) { model.refreshPermissions() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindow?.isVisible == true { onboardingWindow?.makeKeyAndOrderFront(nil) } else { showMain(nil) }
        return true
    }

    private func setIcon(_ symbol: String) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "LocalFlow")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    // MARK: Windows

    func showMain(_ tab: Tab?) {
        if let tab { model.tab = tab }
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "LocalFlow"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: MainView().environmentObject(model))
            w.minSize = NSSize(width: 880, height: 620)
            w.center()
            w.setFrameAutosaveName("LocalFlowMain")
            w.delegate = self
            mainWindow = w
        }
        model.refreshPermissions(); model.modelsVersion += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: OnboardingView().environmentObject(model))
        w.center()
        w.delegate = self
        onboardingWindow = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        let w = n.object as? NSWindow
        if w === onboardingWindow { onboarded = true }
        DispatchQueue.main.async {
            // Free the SwiftUI view tree; it's rebuilt next time the window opens.
            w?.contentView = nil
            if w === self.mainWindow { self.mainWindow = nil }
            if w === self.onboardingWindow { self.onboardingWindow = nil }
            if self.mainWindow == nil && self.onboardingWindow == nil { NSApp.setActivationPolicy(.accessory) }   // back to a pure menu bar app
        }
    }

    @objc private func openMain() { showMain(nil) }
    @objc private func openSettings() { showMain(.settings) }
    @objc private func openHistory() { showMain(.history) }
    @objc private func goTab(_ s: NSMenuItem) {
        if let r = s.representedObject as? String, let t = Tab(rawValue: r) { showMain(t) }
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func sub(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(); let m = NSMenu(title: title); build(m); item.submenu = m; main.addItem(item)
        }
        sub("LocalFlow") { m in
            m.addItem(withTitle: "About LocalFlow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            m.addItem(.separator())
            m.addItem(item("Settings…", #selector(openSettings), key: ","))
            m.addItem(.separator())
            m.addItem(withTitle: "Hide LocalFlow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            m.addItem(withTitle: "Quit LocalFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        sub("Edit") { m in
            m.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            let redo = m.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            redo.keyEquivalentModifierMask = [.command, .shift]
            m.addItem(.separator())
            m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
        sub("Go") { m in
            for (i, t) in Tab.allCases.enumerated() {
                let mi = item(t.title, #selector(goTab(_:)), key: "\(i + 1)"); mi.representedObject = t.rawValue; m.addItem(mi)
            }
        }
        sub("Window") { m in
            m.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            m.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        }
        return main
    }

    // MARK: Hotkey

    private func installMonitors() {
        let flags: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keys: (NSEvent) -> Void = { [weak self] e in self?.handleKeyDown(e) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keys($0); return $0 }) { monitors.append(m) }
    }

    private func handleFlags(_ e: NSEvent) {
        let hk = Settings.hotkey
        guard e.keyCode == hk.keyCode else { return }
        let down = e.modifierFlags.contains(hk.flag)
        if down == keyIsDown { return }
        keyIsDown = down
        down ? hotkeyDown() : hotkeyUp()
    }

    private func handleKeyDown(_ e: NSEvent) {
        switch mode {
        case .holding:
            // Hotkey used as a modifier (e.g. ⌥+e for é): not dictation, abort silently.
            cancelRecording(message: nil)
        case .handsFree where e.keyCode == 53: // Esc
            cancelRecording(message: "Cancelled")
        default: break
        }
    }

    private func hotkeyDown() {
        switch mode {
        case .idle: startRecording()
        case .handsFree: finishRecording()
        default: break
        }
    }

    private func hotkeyUp() {
        guard case .holding(let start) = mode else { return }
        if Date().timeIntervalSince(start) < 0.3 {
            mode = .handsFree        // quick tap → hands-free until next tap
            hud.show(.recording(handsFree: true))
        } else {
            finishRecording()
        }
    }

    private func startRecording() {
        refreshEngineStatus()
        guard model.engineReady else {
            hud.show(.message(model.status == "Speech model not downloaded" ? "Download the speech model in LocalFlow → Models" : model.status,
                              symbol: "exclamationmark.triangle.fill"), autoHide: 2.5)
            if !Downloader.shared.isDownloading(.speech) { showMain(.models) }
            return
        }
        guard AXIsProcessTrusted() else {
            hud.show(.message("Allow Accessibility for LocalFlow", symbol: "exclamationmark.triangle.fill"), autoHide: 2.5)
            model.refreshPermissions(); return
        }
        targetApp = NSWorkspace.shared.frontmostApplication
        do { try recorder.start() } catch {
            hud.show(.message("Mic error: \(error.localizedDescription)", symbol: "mic.slash.fill"), autoHide: 2.5); return
        }
        mode = .holding(Date())
        model.phase = .recording
        speech.wake()          // loads while you talk (~0.3 s)
        TextCleaner.warmUp()
        if Settings.sounds { NSSound(named: "Tink")?.play() }
        hud.model.levels = Array(repeating: 0, count: hud.model.levels.count)
        hud.model.liveText = ""
        hud.show(.recording(handsFree: false))
        setIcon("waveform.circle.fill")
        startPreview()
    }

    /// Live readout: re-transcribe the last ~12 s every ~0.7 s while recording (one request in flight at a time).
    private func startPreview() {
        previewTask?.cancel()
        guard Settings.livePreview else { return }
        session += 1
        let my = session
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            while let self, !Task.isCancelled, self.session == my, self.recorder.isRunning {
                let audio = self.recorder.snapshot(lastSeconds: 12)
                var peak: Float = 0; for s in audio.suffix(16000 * 3) { peak = max(peak, abs(s)) }
                if self.speech.ready && audio.count >= 12800 && peak > 0.01 {
                    let padded = audio + [Float](repeating: 0, count: 3200)
                    if let raw = try? await Engines.transcribe(wav: Recorder.wav(padded), prompt: TextCleaner.vocabularyPrompt()),
                       !Task.isCancelled, self.session == my, self.recorder.isRunning {
                        let t = TextCleaner.applyVocabulary(TextCleaner.basic(raw))
                        if !t.isEmpty && !TextCleaner.isHallucination(t) {
                            self.hud.model.liveText = (audio.count >= 12 * 16000 ? "… " : "") + t
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    private func stopPreview() { previewTask?.cancel(); previewTask = nil; session += 1 }

    private func cancelRecording(message: String?) {
        stopPreview()
        _ = recorder.stop()
        mode = .idle
        model.phase = .idle
        setIcon("waveform")
        if let message { hud.show(.message(message, symbol: "xmark.circle.fill"), autoHide: 0.8) } else { hud.show(.hidden) }
        sleepModels()
    }

    private func finishRecording() {
        stopPreview()
        let samples = recorder.stop()
        mode = .busy
        setIcon("ellipsis.circle")
        if Settings.sounds { NSSound(named: "Pop")?.play() }

        let seconds = Double(samples.count) / 16000
        var peak: Float = 0; for s in samples { peak = max(peak, abs(s)) }
        guard seconds >= 0.35, peak > 0.01 else {
            mode = .idle; model.phase = .idle; setIcon("waveform"); sleepModels()
            hud.show(.message("Didn't catch that", symbol: "ear.trianglebadge.exclamationmark"), autoHide: 0.9); return
        }
        hud.show(.transcribing)
        model.phase = .transcribing
        let app = targetApp
        Task { @MainActor in
            defer { self.mode = .idle; self.model.phase = .idle; self.setIcon("waveform"); self.sleepModels() }
            guard await speech.waitUntilReady() else {
                hud.show(.message("Speech engine didn't start", symbol: "exclamationmark.triangle.fill"), autoHide: 1.8); return
            }
            do {
                // Pad with 0.3 s of silence; whisper clips the final word less often.
                let padded = samples + [Float](repeating: 0, count: 4800)
                let raw = try await Engines.transcribe(wav: Recorder.wav(padded), prompt: TextCleaner.vocabularyPrompt())
                var text = TextCleaner.applyVocabulary(TextCleaner.basic(raw))
                if text.isEmpty || TextCleaner.isHallucination(text) {
                    hud.show(.message("Didn't catch that", symbol: "ear.trianglebadge.exclamationmark"), autoHide: 0.9); return
                }
                var used: String? = nil
                if Settings.smartFormat && TextCleaner.needsSmartFormat(text, raw: raw) {
                    if Settings.formatTier != "xs" { hud.show(.formatting); model.phase = .formatting }
                    text = TextCleaner.applyVocabulary(await TextCleaner.smartFormat(text))
                    used = model.currentTier.name
                }
                model.record(HistoryItem(date: Date(), text: text,
                                         raw: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                                         app: app?.localizedName, bundleID: app?.bundleIdentifier,
                                         seconds: seconds, model: used))
                if let t = app, NSWorkspace.shared.frontmostApplication?.processIdentifier != t.processIdentifier {
                    t.activate(); try? await Task.sleep(nanoseconds: 150_000_000)
                }
                Paster.paste(text)
                hud.show(.hidden)
            } catch {
                hud.show(.message("Transcription failed", symbol: "exclamationmark.triangle.fill"), autoHide: 1.5)
            }
        }
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        model.refreshPermissions()
        let (label, _, _) = phaseInfo(model)
        let head = NSMenuItem(title: "LocalFlow · \(label)", action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        let how = NSMenuItem(title: "Hold \(Settings.hotkey.label) to talk · tap for hands-free", action: nil, keyEquivalent: "")
        how.isEnabled = false; menu.addItem(how)
        if !AXIsProcessTrusted() || model.micStatus != .authorized {
            menu.addItem(item("⚠︎ Finish setting up permissions…", #selector(openSettings)))
        }
        menu.addItem(.separator())
        let open = item("Open LocalFlow", #selector(openMain), key: "o"); open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(open)

        // Recent
        let hist = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        hist.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let hm = NSMenu()
        let items = model.history.prefix(10)
        if items.isEmpty { let e = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: ""); e.isEnabled = false; hm.addItem(e) }
        else {
            let h = NSMenuItem(title: "Click to copy", action: nil, keyEquivalent: ""); h.isEnabled = false; hm.addItem(h)
        }
        for h in items {
            let title = h.text.count > 70 ? String(h.text.prefix(70)).trimmingCharacters(in: .whitespaces) + "…" : h.text
            let mi = item(title.replacingOccurrences(of: "\n", with: " ⏎ "), #selector(copyHistory(_:)))
            mi.representedObject = h.text; mi.toolTip = h.text
            hm.addItem(mi)
        }
        if !items.isEmpty { hm.addItem(.separator()); hm.addItem(item("Show all history", #selector(openHistory))) }
        hist.submenu = hm; menu.addItem(hist)
        menu.addItem(.separator())

        // Formatting
        let pol = item("Smart formatting", #selector(togglePolish)); pol.state = model.smartFormat ? .on : .off
        pol.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(pol)
        let mItem = NSMenuItem(title: "Model: \(model.currentTier.name)", action: nil, keyEquivalent: "")
        mItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        let mm = NSMenu()
        for t in Tier.all {
            var title = "\(t.name)  ·  \(t.sizeLabel)  ·  \(t.accuracy)/\(Tier.testCases)"
            if t.id == model.recommended.id { title += "  ★" }
            if !t.isInstalled { title += "  (not downloaded)" }
            let mi = item(title, #selector(pickModel(_:))); mi.representedObject = t.id
            mi.state = t.id == model.formatTier ? .on : .off
            mi.isEnabled = t.isInstalled && model.smartFormat
            mi.toolTip = t.blurb
            mm.addItem(mi)
        }
        mm.addItem(.separator())
        mm.addItem(item("Compare models…", #selector(goTab(_:)), represented: Tab.models.rawValue))
        mItem.submenu = mm; menu.addItem(mItem)
        menu.addItem(.separator())

        let settings = item("Settings…", #selector(openSettings), key: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit LocalFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ sel: Selector, key: String = "", represented: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key); mi.target = self
        if let represented { mi.representedObject = represented }
        return mi
    }

    @objc private func copyHistory(_ s: NSMenuItem) {
        guard let t = s.representedObject as? String else { return }
        model.copy(t)
        hud.show(.message("Copied", symbol: "doc.on.doc.fill"), autoHide: 0.8)
    }
    @objc private func pickModel(_ s: NSMenuItem) { if let r = s.representedObject as? String { model.formatTier = r } }
    @objc private func togglePolish() { model.smartFormat.toggle() }

    /// Keep the engine log small: start over once it passes 2 MB.
    private func trimLog() {
        let size = (try? FileManager.default.attributesOfItem(atPath: Config.logURL.path)[.size] as? Int) ?? 0
        if size > 2_000_000 { try? FileManager.default.removeItem(at: Config.logURL) }
    }

    private func seedVocabulary() {
        guard !FileManager.default.fileExists(atPath: Config.vocabURL.path) else { return }
        VocabStore.save([])
    }
}

// LocalFlow --snapshot <dir> → renders every page (light + dark) and the HUD offscreen to PNGs, for visual checks.
func runSnapshots(_ dir: String) {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let m = AppModel.shared
    m.engineReady = true; m.engineLoaded = false; m.status = "Ready"
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    func shoot<V: View>(_ v: V, _ name: String, _ size: NSSize, dark: Bool) {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hv = NSHostingView(rootView: v.environmentObject(m).environment(\.snapshot, true)); w.contentView = hv
        w.setFrameOrigin(NSPoint(x: -5000, y: -5000)); w.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return }
        hv.cacheDisplay(in: hv.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)\(dark ? "-dark" : "").png"))
        w.orderOut(nil)
    }
    for dark in [false, true] {
        for t in Tab.allCases { m.tab = t; shoot(MainView(), t.rawValue, NSSize(width: 1040, height: t == .home ? 1500 : t == .models ? 1400 : 1150), dark: dark) }
        for st in 0..<5 { shoot(OnboardingView(step: st), "onboarding\(st)", NSSize(width: 580, height: 560), dark: dark) }
    }
    let hm = HUDModel(); hm.levels = (0..<28).map { i in CGFloat(abs(sin(Double(i) * 0.7))) * 0.8 }
    for (n, s) in [("hud-rec", HUDState.recording(handsFree: true)), ("hud-format", .formatting), ("hud-msg", .message("Didn't catch that", symbol: "ear.trianglebadge.exclamationmark"))] {
        hm.state = s; hm.liveText = ""; shoot(HUDView(model: hm).background(Color.gray), n, NSSize(width: 680, height: 220), dark: true)
    }
    for (n, t) in [("hud-live-short", "Remind me to call the dentist"), ("hud-live-long", "Okay so for the show on Saturday we need two more vocal mics, the long XLR cables, actually the short ones, and somebody needs to pick up the rental van from the place on Main Street before noon")] {
        hm.state = .recording(handsFree: false); hm.liveText = t
        shoot(HUDView(model: hm).background(Color.gray), n, NSSize(width: 680, height: 220), dark: true)
    }
}
