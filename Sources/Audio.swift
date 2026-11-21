// LocalFlow: microphone capture (16 kHz mono for Whisper) and pasting into the focused app.

import Cocoa
import AVFoundation

// MARK: - Recorder (16 kHz mono)

final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    var onLevel: ((Float) -> Void)?
    private(set) var isRunning = false

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw NSError(domain: "rec", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
            guard let self else { return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / inFormat.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            guard err == nil, let ch = out.floatChannelData?[0] else { return }
            let n = Int(out.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: ch, count: n))
            var sum: Float = 0
            for s in chunk { sum += s * s }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
            self.onLevel?(rms)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Copy of the most recent audio while still recording (for the live preview).
    func snapshot(lastSeconds: Double) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let n = Int(lastSeconds * 16000)
        return samples.count > n ? Array(samples.suffix(n)) : samples
    }

    /// Stops and returns captured samples.
    func stop() -> [Float] {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        let dataLen = UInt32(samples.count * 2)
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataLen)
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataLen)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}

// MARK: - Paste

enum Paster {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var m: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { m[t] = d } }
            return m
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeAfterSet = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)

        guard Settings.restoreClipboard, !saved.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pb.changeCount == changeAfterSet else { return } // user copied something new meanwhile
            pb.clearContents()
            let items = saved.map { m -> NSPasteboardItem in
                let it = NSPasteboardItem(); for (t, d) in m { it.setData(d, forType: t) }; return it
            }
            pb.writeObjects(items)
        }
    }
}

