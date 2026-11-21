// LocalFlow — SwiftUI interface: design system, floating HUD, main window (Home/History/Dictionary/Models/Settings), onboarding.

import Cocoa
import SwiftUI
import Charts
import AVFoundation

// MARK: - Design system

enum Brand {
    static let violet = Color(red: 0.42, green: 0.32, blue: 0.97)
    static let blue = Color(red: 0.34, green: 0.47, blue: 0.99)
    static let cyan = Color(red: 0.16, green: 0.76, blue: 1.0)
    static let gradient = LinearGradient(colors: [violet, blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let horizontal = LinearGradient(colors: [violet, cyan], startPoint: .leading, endPoint: .trailing)
    static let vertical = LinearGradient(colors: [cyan, violet], startPoint: .top, endPoint: .bottom)

    static let pageBG = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.115, alpha: 1) : NSColor(white: 0.962, alpha: 1)
    })
    static let cardBG = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.165, alpha: 1) : .white
    })
    static let good = Color(red: 0.20, green: 0.74, blue: 0.42)
    static let warn = Color(red: 0.98, green: 0.62, blue: 0.16)
    static let rec = Color(red: 1.0, green: 0.27, blue: 0.33)
}

struct Card: ViewModifier {
    var padding: CGFloat = 20
    var highlight = false
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.cardBG))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlight ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)),
                                  lineWidth: highlight ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
extension View {
    func card(padding: CGFloat = 20, highlight: Bool = false) -> some View { modifier(Card(padding: padding, highlight: highlight)) }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = .behindWindow; v.state = .followsWindowActiveState; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct AppGlyph: View {
    var size: CGFloat = 32
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "waveform").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
            .shadow(color: Brand.violet.opacity(0.35), radius: size * 0.15, y: size * 0.06)
    }
}

struct Keycap: View {
    let label: String
    var size: CGFloat = 22
    var dark = false
    var body: some View {
        Text(label)
            .font(.system(size: size * 0.8, weight: .semibold, design: .rounded))
            .padding(.horizontal, size * 0.45).padding(.vertical, size * 0.18)
            .frame(minWidth: size * 1.6)
            .foregroundStyle(dark ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(dark ? Color.white.opacity(0.18) : Brand.cardBG)
                    .shadow(color: .black.opacity(dark ? 0.2 : 0.12), radius: 0, y: size * 0.08)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.35) : Color.primary.opacity(0.15)))
    }
}

struct Badge: View {
    let text: String
    var color: Color = Brand.violet
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    var body: some View {
        ZStack {
            if pulsing {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    Circle().fill(color.opacity(0.4 * (1 - t))).frame(width: 8 + 10 * t, height: 8 + 10 * t)
                }
            }
            Circle().fill(color).frame(width: 8, height: 8)
        }.frame(width: 18, height: 18)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold))
                Text(subtitle).font(.system(size: 13.5)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}
extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var snapshot: Bool { get { self[SnapshotKey.self] } set { self[SnapshotKey.self] = newValue } } }

struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.snapshot) private var snapshot
    var body: some View {
        if snapshot { inner.frame(maxHeight: .infinity, alignment: .top) } else { ScrollView { inner } }
    }
    private var inner: some View {
        VStack(alignment: .leading, spacing: 22) { content }
            .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 36)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

struct SectionTitle: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Brand.violet) }
            Text(text).font(.system(size: 15, weight: .semibold))
        }
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = .secondary
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(hover ? Color.primary : tint)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.09 : 0)))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Capsule().fill(enabled ? AnyShapeStyle(Brand.horizontal) : AnyShapeStyle(Color.gray.opacity(0.4))))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > b.minX && x + sz.width > b.maxX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

enum AppIcons {
    static var cache: [String: NSImage] = [:]
    static func icon(_ bundleID: String?) -> NSImage? {
        guard let id = bundleID else { return nil }
        if let i = cache[id] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path); cache[id] = i; return i
    }
}

struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 30
    var body: some View {
        if let img = AppIcons.icon(bundleID) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Brand.violet.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(Image(systemName: "text.cursor").font(.system(size: size * 0.42)).foregroundStyle(Brand.violet))
        }
    }
}

/// Text box with placeholder (for "try it" areas).
struct NoteEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 90
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
            if text.isEmpty {
                Text(placeholder).font(.system(size: 14)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 15).padding(.vertical, 10).allowsHitTesting(false)
            }
        }
        .frame(height: minHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

func phaseInfo(_ m: AppModel) -> (String, Color, Bool) {
    switch m.phase {
    case .recording: return ("Listening", Brand.rec, true)
    case .transcribing: return ("Transcribing", Brand.violet, true)
    case .formatting: return ("Formatting", Brand.cyan, true)
    case .idle:
        if m.engineReady { return m.permissionsOK ? ("Ready", Brand.good, false) : ("Needs permissions", Brand.warn, false) }
        return (m.status, Brand.warn, true)
    }
}

// MARK: - HUD (floating pill at the bottom of the screen)

enum HUDState: Equatable { case hidden, recording(handsFree: Bool), transcribing, formatting, message(String, symbol: String = "info.circle.fill") }

final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    @Published var levels: [CGFloat] = Array(repeating: 0, count: 28)
    @Published var liveText = ""
    var startedAt = Date()
    func push(_ rms: Float) {
        let v = CGFloat(min(1, sqrt(Double(rms)) * 3.2))
        levels.removeFirst(); levels.append(v)
    }
}

struct HUDWaveform: View {
    let levels: [CGFloat]
    var body: some View {
        Rectangle().fill(Brand.horizontal)
            .mask(
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, l in
                        Capsule().frame(width: 3, height: 3 + l * 22)
                    }
                }
            )
            .frame(width: CGFloat(levels.count) * 5.5, height: 26)
            .animation(.linear(duration: 0.06), value: levels)
    }
}

struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    let p = (sin(t * 7 - Double(i) * 0.8) + 1) / 2
                    Circle().fill(Brand.horizontal).frame(width: 6, height: 6)
                        .offset(y: -4 * p).opacity(0.5 + 0.5 * p)
                }
            }.frame(height: 14)
        }
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var showLive: Bool {
        guard !model.liveText.isEmpty else { return false }
        switch model.state { case .recording, .transcribing, .formatting: return true; default: return false }
    }
    var body: some View {
        VStack(spacing: 8) {
            if showLive {
                LiveTranscript(text: model.liveText, settled: model.state != .recording(handsFree: false) && model.state != .recording(handsFree: true))
                    .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
            content
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.07).opacity(0.92)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
                .fixedSize()
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showLive)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .recording(let handsFree):
            HStack(spacing: 12) {
                StatusDot(color: Brand.rec, pulsing: true)
                HUDWaveform(levels: model.levels)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let s = max(0, Int(ctx.date.timeIntervalSince(model.startedAt)))
                    Text(String(format: "%d:%02d", s / 60, s % 60))
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                if handsFree {
                    Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 16)
                    HStack(spacing: 5) {
                        Text("Hands-free").foregroundStyle(.white.opacity(0.9))
                        Text("tap \(Settings.hotkey.keycap) to finish · esc to cancel").foregroundStyle(.white.opacity(0.55))
                    }.font(.system(size: 11.5, weight: .medium))
                }
            }
        case .transcribing:
            HStack(spacing: 10) { BouncingDots(); Text("Transcribing").hudText() }
        case .formatting:
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.horizontal)
                Text("Formatting").hudText()
            }
        case .message(let m, let symbol):
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text(m).hudText()
            }
        case .hidden:
            EmptyView()
        }
    }
}

/// Live readout above the pill: newest words stay visible, older ones scroll off the top.
struct LiveTranscript: View {
    let text: String
    var settled = false
    var body: some View {
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).width
        Text(text).lineLimit(3).truncationMode(.head).multilineTextAlignment(.leading)
            .frame(width: min(520, ceil(w) + 4), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(settled ? 0.6 : 0.95))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.07).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
            .animation(.easeOut(duration: 0.15), value: text)
    }
}

private extension Text {
    func hudText() -> some View { font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.9)) }
}

final class HUD {
    let model = HUDModel()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 220),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar; p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: HUDView(model: model))
        return p
    }()
    private var hideWork: DispatchWorkItem?

    func show(_ s: HUDState, autoHide: Double? = nil) {
        hideWork?.cancel()
        if case .recording = s, case .recording = model.state {} else if case .recording = s { model.startedAt = Date() }
        model.state = s
        if s == .hidden { panel.orderOut(nil); model.liveText = ""; return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 2))
        }
        panel.orderFrontRegardless()
        if let t = autoHide {
            let w = DispatchWorkItem { [weak self] in self?.show(.hidden) }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
    }
}

// MARK: - Main window

struct MainView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 224)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            ZStack {
                Brand.pageBG
                Group {
                    switch m.tab {
                    case .home: HomeView()
                    case .history: HistoryView()
                    case .dictionary: DictionaryView()
                    case .models: ModelsView()
                    case .settings: SettingsView()
                    }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 880, minHeight: 620)
        .animation(.easeOut(duration: 0.15), value: m.tab)
    }
}

struct Sidebar: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let (label, color, pulsing) = phaseInfo(m)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 11) {
                AppGlyph(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LocalFlow").font(.system(size: 15, weight: .bold))
                    HStack(spacing: 2) {
                        StatusDot(color: color, pulsing: pulsing).scaleEffect(0.8).frame(width: 14, height: 14)
                        Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 50).padding(.bottom, 20)

            ForEach(Tab.allCases) { t in SidebarRow(tab: t) }

            Spacer()

            if !m.permissionsOK {
                Button { m.tab = .settings } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
                        Text("Permissions needed").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.warn.opacity(0.12)))
                }.buttonStyle(.plain).padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("100% on-device", systemImage: "lock.shield.fill")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Brand.violet)
                Text("Your voice and words never leave this Mac. No account, no cloud.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.violet.opacity(0.08)))
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar))
    }
}

struct SidebarRow: View {
    @EnvironmentObject var m: AppModel
    let tab: Tab
    @State private var hover = false
    var body: some View {
        let selected = m.tab == tab
        Button { m.tab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? tab.symbol + (tab == .history || tab == .models ? "" : ".fill") : tab.symbol)
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary))
                Text(tab.title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer()
                if tab == .history && !m.history.isEmpty {
                    Text("\(m.history.count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Brand.violet.opacity(0.14) : Color.primary.opacity(hover ? 0.05 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Home

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    @State private var tryText = ""

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        Page {
            PageHeader(title: greeting,
                       subtitle: m.stats.today > 0 ? "You've dictated \(m.stats.today.formatted()) words today." : "Ready when you are. Hold the key and start talking.")

            if !m.permissionsOK { PermissionBanner() }

            HeroCard()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "Try it here", symbol: "text.cursor")
                    Spacer()
                    if !tryText.isEmpty { Button("Clear") { tryText = "" }.buttonStyle(.link) }
                }
                NoteEditor(text: $tryText,
                           placeholder: "Click here, hold \(m.hotkey.name), and say: \"Grocery list: eggs, milk, bread. Actually, not bread, make that bagels.\"")
            }.card()

            StatsGrid()

            HStack(alignment: .top, spacing: 18) {
                WeekChart().frame(maxWidth: .infinity)
                FormattingSummary().frame(width: 280)
            }

            RecentCard()
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 22)).foregroundStyle(Brand.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("LocalFlow needs a permission to work").font(.system(size: 13.5, weight: .semibold))
                Text(m.micStatus != .authorized ? "Microphone access lets it hear you." : "Accessibility lets it paste text into other apps.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(m.micStatus != .authorized ? "Allow microphone" : "Open Accessibility") {
                m.micStatus != .authorized ? m.requestMic() : m.requestAccessibility()
            }.buttonStyle(PrimaryButtonStyle())
        }
        .card(padding: 16)
    }
}

struct HeroCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let (label, _, _) = phaseInfo(m)
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.gradient)
            // decorative rings
            GeometryReader { g in
                ZStack {
                    ForEach(0..<4) { i in
                        Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1.5)
                            .frame(width: 180 + CGFloat(i) * 90, height: 180 + CGFloat(i) * 90)
                    }
                }.position(x: g.size.width - 110, y: g.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        StatusDot(color: m.phase == .recording ? Brand.rec : .white, pulsing: m.phase != .idle).scaleEffect(0.8)
                        Text(label).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.18)))

                    HStack(spacing: 10) {
                        Text("Hold")
                        Keycap(label: m.hotkey.keycap, size: 28, dark: true)
                        Text("and talk")
                    }
                    .font(.system(size: 30, weight: .bold))

                    Text("\(m.hotkey.name) works in any app. Let go and your words appear where you're typing. Tap it once for hands-free, press esc to cancel.")
                        .font(.system(size: 13.5)).opacity(0.88).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Orb(phase: m.phase)
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .frame(minHeight: 200)
        .shadow(color: Brand.violet.opacity(0.3), radius: 18, y: 8)
    }
}

struct Orb: View {
    let phase: Phase
    var icon: String {
        switch phase { case .idle: "mic.fill"; case .recording: "waveform"; case .transcribing: "text.bubble.fill"; case .formatting: "sparkles" }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: phase == .idle)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let speed = phase == .recording ? 5.0 : 2.5
            let pulse = phase == .idle ? 1.0 : 1 + 0.07 * sin(t * speed)
            ZStack {
                Circle().fill(.white.opacity(0.10)).frame(width: 136, height: 136).scaleEffect(pulse * 1.04)
                Circle().fill(.white.opacity(0.16)).frame(width: 104, height: 104).scaleEffect(pulse)
                Circle().fill(.white).frame(width: 72, height: 72).shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                Image(systemName: icon).font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(phase == .recording ? AnyShapeStyle(Brand.rec) : AnyShapeStyle(Brand.gradient))
            }
        }
        .frame(width: 140, height: 140)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
    }
}

struct StatTile: View {
    let symbol: String
    let value: String
    let label: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.gradient)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.violet.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .card(padding: 16)
    }
}

struct StatsGrid: View {
    @EnvironmentObject var m: AppModel
    var saved: String {
        let mins = m.stats.minutesSaved
        return mins >= 60 ? String(format: "%.1f h", mins / 60) : "\(Int(mins.rounded())) min"
    }
    var body: some View {
        let s = m.stats
        HStack(spacing: 14) {
            StatTile(symbol: "text.word.spacing", value: s.words.formatted(), label: "Words dictated", detail: "\(s.dictations.formatted()) dictations")
            StatTile(symbol: "speedometer", value: "\(s.wpm)", label: "Words per minute", detail: "Typing averages about 40")
            StatTile(symbol: "hourglass", value: saved, label: "Time saved", detail: "Compared with typing")
            StatTile(symbol: "flame.fill", value: "\(s.streak)", label: s.streak == 1 ? "Day streak" : "Day streak", detail: s.streak > 0 ? "Keep it going" : "Dictate today to start one")
        }
    }
}

struct WeekChart: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let days = m.stats.lastDays(7)
        let total = days.reduce(0) { $0 + $1.words }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "This week", symbol: "chart.bar.fill")
                Spacer()
                Text("\(total.formatted()) words").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Chart(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Words", d.words), width: .ratio(0.55))
                    .foregroundStyle(Brand.vertical)
                    .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.06)); AxisValueLabel() } }
            .frame(height: 170)
        }
        .card()
    }
}

struct FormattingSummary: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let tier = m.currentTier
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Smart formatting", symbol: "sparkles")
            if m.smartFormat {
                HStack(spacing: 12) {
                    Text(tier.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Brand.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tier.name) model").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text("\(tier.sizeLabel) · \(tier.speed)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Text("Fixes self-corrections, builds lists, and drops filler words. Plain sentences skip the model entirely.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Off. Text is pasted exactly as transcribed, with basic punctuation cleanup.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Manage models") { m.tab = .models }.buttonStyle(.link).font(.system(size: 12.5, weight: .medium))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

struct RecentCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Recent", symbol: "clock")
                Spacer()
                if !m.history.isEmpty { Button("See all") { m.tab = .history }.buttonStyle(.link).font(.system(size: 12.5, weight: .medium)) }
            }
            if m.history.isEmpty {
                EmptyState(symbol: "waveform", title: "No dictations yet", message: "Everything you dictate shows up here, so you can copy it again later.")
            } else {
                VStack(spacing: 2) { ForEach(m.history.prefix(5)) { HistoryRow(item: $0, compact: true) } }
            }
        }
        .card(padding: 16)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(Brand.gradient)
                .frame(width: 64, height: 64).background(Circle().fill(Brand.violet.opacity(0.08)))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26)
    }
}

// MARK: History

struct HistoryRow: View {
    @EnvironmentObject var m: AppModel
    let item: HistoryItem
    var compact = false
    @State private var hover = false
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(bundleID: item.bundleID, size: 30)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.text)
                    .font(.system(size: 13.5))
                    .lineLimit(expanded ? nil : (compact ? 2 : 3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if expanded, let raw = item.raw, raw != item.text {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WHAT YOU SAID").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
                        Text(raw).font(.system(size: 12.5)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
                meta
            }
            HStack(spacing: 2) {
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy", tint: copied ? Brand.good : .secondary) { copy(item.text) }
                if !compact { IconButton(symbol: "trash", help: "Delete") { withAnimation { m.delete(item) } } }
            }
            .opacity(hover || copied ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(hover ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
        .contextMenu {
            Button("Copy") { copy(item.text) }
            if let raw = item.raw, raw != item.text { Button("Copy what you said") { copy(raw) } }
            Divider()
            Button("Delete", role: .destructive) { m.delete(item) }
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Text(item.date, style: .time)
            if let a = item.app { sep; Text(a) }
            sep; Text("\(item.words) words")
            if let s = item.seconds { sep; Text(s < 60 ? String(format: "%.0fs", s) : String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)) }
            if item.model != nil { Badge(text: "Formatted", symbol: "sparkles").padding(.leading, 2) }
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
    }
    private var sep: some View { Text("·").foregroundStyle(.tertiary) }

    private func copy(_ t: String) {
        m.copy(t); copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

struct HistoryView: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @State private var confirmClear = false

    var filtered: [HistoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? m.history : m.history.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.app ?? "").localizedCaseInsensitiveContains(q)
        }
    }
    var groups: [(Date, [HistoryItem])] {
        let cal = Calendar.current
        return Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }
    func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        Page {
            PageHeader(title: "History", subtitle: m.keepHistory ? "Everything you've dictated, stored only on this Mac." : "History is off. New dictations aren't saved.") {
                HStack(spacing: 8) {
                    Button { export() } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(m.history.isEmpty)
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear", systemImage: "trash") }.disabled(m.history.isEmpty)
                }.controlSize(.regular)
            }
            .confirmationDialog("Delete all \(m.history.count) dictations?", isPresented: $confirmClear) {
                Button("Delete all", role: .destructive) { withAnimation { m.clearHistory() } }
            } message: { Text("This can't be undone. Your stats are kept.") }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search dictations or apps", text: $query).textFieldStyle(.plain).font(.system(size: 13.5))
                if !query.isEmpty { IconButton(symbol: "xmark.circle.fill", help: "Clear search") { query = "" } }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Brand.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            if filtered.isEmpty {
                EmptyState(symbol: query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                           title: query.isEmpty ? "Nothing here yet" : "No matches",
                           message: query.isEmpty ? "Hold \(m.hotkey.name) anywhere and start talking. Your dictations will appear here." : "Try a different word or app name.")
                    .card()
            } else {
                ForEach(groups, id: \.0) { day, items in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(dayLabel(day)).font(.system(size: 13, weight: .semibold))
                            Text("\(items.reduce(0) { $0 + $1.words }.formatted()) words").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(.leading, 4)
                        VStack(spacing: 2) { ForEach(items) { HistoryRow(item: $0) } }.card(padding: 8)
                    }
                }
                Text("Click a dictation to see what you originally said. LocalFlow keeps your latest \(History.limit).")
                    .font(.system(size: 11.5)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
        }
    }

    private func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "LocalFlow History.txt"
        p.allowedContentTypes = [.plainText]
        guard p.runModal() == .OK, let url = p.url else { return }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        let s = m.history.map { "[\(f.string(from: $0.date))\($0.app.map { " · \($0)" } ?? "")]\n\($0.text)\n" }.joined(separator: "\n")
        try? s.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: Dictionary

struct DictionaryView: View {
    @State private var entries: [VocabEntry] = VocabStore.load()
    @State private var newWord = ""
    @State private var fixFrom = ""
    @State private var fixTo = ""

    var terms: [VocabEntry] { entries.filter { $0.from == nil } }
    var fixes: [VocabEntry] { entries.filter { $0.from != nil } }

    var body: some View {
        Page {
            PageHeader(title: "Dictionary", subtitle: "Teach LocalFlow names, jargon and words it keeps getting wrong.") {
                Button { NSWorkspace.shared.open(Config.vocabURL) } label: { Label("Edit as text", systemImage: "doc.text") }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Words & names", symbol: "textformat")
                Text("Always spelled exactly as written. \"mac book\" becomes \"MacBook\", \"github\" becomes \"GitHub\".")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Add a word, name or phrase", text: $newWord)
                        .textFieldStyle(.roundedBorder).controlSize(.large).onSubmit(addWord)
                    Button("Add", action: addWord).buttonStyle(PrimaryButtonStyle())
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if terms.isEmpty {
                    Text("No words yet.").font(.system(size: 12.5)).foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 8) { ForEach(terms) { e in Chip(text: e.to) { remove(e) } } }
                }
            }.card()

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Replacements", symbol: "arrow.left.arrow.right")
                Text("When speech recognition keeps hearing a word wrong, swap it for the right one.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("When it writes", text: $fixFrom).textFieldStyle(.roundedBorder).controlSize(.large)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Replace with", text: $fixTo).textFieldStyle(.roundedBorder).controlSize(.large).onSubmit(addFix)
                    Button("Add", action: addFix).buttonStyle(PrimaryButtonStyle())
                        .disabled(fixFrom.trimmingCharacters(in: .whitespaces).isEmpty || fixTo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if fixes.isEmpty {
                    Text("No replacements yet. Example: Jon → John").font(.system(size: 12.5)).foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(fixes) { e in
                            HStack(spacing: 10) {
                                Text(e.from ?? "").foregroundStyle(.secondary).strikethrough(color: .secondary.opacity(0.6))
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.violet)
                                Text(e.to).fontWeight(.semibold)
                                Spacer()
                                IconButton(symbol: "trash", help: "Remove") { remove(e) }
                            }
                            .font(.system(size: 13.5)).padding(.vertical, 8).padding(.horizontal, 4)
                            if e.id != fixes.last?.id { Divider() }
                        }
                    }
                }
            }.card()

            Label("Changes apply to your next dictation.", systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .onAppear { entries = VocabStore.load() }
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !terms.contains(where: { $0.to == w }) else { newWord = ""; return }
        withAnimation(.snappy) { entries.append(VocabEntry(from: nil, to: w)) }
        newWord = ""; VocabStore.save(entries)
    }
    private func addFix() {
        let f = fixFrom.trimmingCharacters(in: .whitespaces), t = fixTo.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !t.isEmpty else { return }
        withAnimation(.snappy) { entries.append(VocabEntry(from: f, to: t)) }
        fixFrom = ""; fixTo = ""; VocabStore.save(entries)
    }
    private func remove(_ e: VocabEntry) {
        withAnimation(.snappy) { entries.removeAll { $0.id == e.id } }
        VocabStore.save(entries)
    }
}

struct Chip: View {
    let text: String
    let onDelete: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13, weight: .medium))
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hover ? Color.primary : Color.secondary)
            }.buttonStyle(.plain).help("Remove")
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 7)
        .background(Capsule().fill(Brand.violet.opacity(hover ? 0.16 : 0.1)))
        .overlay(Capsule().strokeBorder(Brand.violet.opacity(0.18)))
        .onHover { hover = $0 }
    }
}

// MARK: Models

struct ModelsView: View {
    @EnvironmentObject var m: AppModel
    var ramGB: Int { Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()) }

    var body: some View {
        Page {
            PageHeader(title: "Models", subtitle: "Everything runs on this Mac. Pick the size that fits how you work.")

            // Speech recognition
            HStack(spacing: 16) {
                Image(systemName: "waveform").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Brand.gradient))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Speech recognition").font(.system(size: 15, weight: .semibold))
                        if !ModelFile.speech.isInstalled { Badge(text: "Not downloaded", color: Brand.warn) }
                        else if !m.engineReady { Badge(text: m.status, color: Brand.warn) }
                        else if m.engineLoaded { Badge(text: "Loaded", color: Brand.good) }
                        else { Badge(text: "Sleeping", color: .secondary) }
                    }
                    Text("Whisper Large v3 Turbo · \(ModelFile.speech.sizeLabel) · Apple GPU (Metal)").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Text(m.engineLoaded ? "In memory now. Unloads when you stop dictating (Settings → Memory)."
                                        : "Loads in about 0.3 s when you press the key, while you talk.")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                Spacer()
                DownloadControl(file: .speech)
            }.card()
            .id(m.modelsVersion)

            if let e = m.downloadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
                    Text("Download failed: \(e)").font(.system(size: 12.5))
                    Spacer()
                    Button("Dismiss") { m.downloadError = nil }.controlSize(.small)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Brand.warn.opacity(0.1)))
            }

            // Smart formatting
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "Smart formatting", symbol: "sparkles")
                        Text("A model trained only for English dictation. It understands \"no wait, make that 4\", turns spoken lists into real lists, and drops filler words. It can't answer or rewrite you.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 20)
                    Toggle("", isOn: $m.smartFormat).toggleStyle(.switch).labelsHidden().tint(Brand.violet)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(Tier.all, id: \.id) { TierCard(tier: $0) }
                }
                .disabled(!m.smartFormat).opacity(m.smartFormat ? 1 : 0.5)

                HStack(spacing: 6) {
                    Image(systemName: "memorychip").foregroundStyle(.secondary)
                    Text("This Mac has \(ramGB) GB of memory. ★ marks the most accurate model that fits comfortably. Accuracy is out of \(Tier.testCases) tricky test sentences the models never saw in training.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.card()

            Playground()
        }
    }
}

struct Meter: View {
    let label: String
    let value: Double
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(text).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(Brand.horizontal).frame(width: max(6, g.size.width * value))
                }
            }.frame(height: 6)
        }
    }
}

/// "Download" button that turns into a progress bar with a cancel button.
struct DownloadControl: View {
    @EnvironmentObject var m: AppModel
    let file: ModelFile
    var body: some View {
        if let p = m.progress(file) {
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 110).tint(Brand.violet)
                Text("\(Int(p * 100))%").font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                Button { m.cancelDownload(file) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Cancel download")
            }
        } else if !file.isInstalled {
            Button { m.download(file) } label: { Label("Download \(file.sizeLabel)", systemImage: "arrow.down.circle") }
        }
    }
}

struct TierCard: View {
    @EnvironmentObject var m: AppModel
    let tier: Tier
    @State private var hover = false
    var body: some View {
        let _ = m.modelsVersion
        let installed = tier.isInstalled
        let selected = m.formatTier == tier.id
        let recommended = m.recommended.id == tier.id
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(tier.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(selected ? .white : Brand.violet)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.violet.opacity(0.1))))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.name).font(.system(size: 14.5, weight: .semibold))
                    Text("\(tier.sizeLabel) · \(tier.file == nil ? "Built in" : installed ? "Downloaded" : "Download")").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if recommended { Badge(text: "Recommended", color: Brand.violet, symbol: "star.fill") }
                    if !tier.fits { Badge(text: "Heavy for this Mac", color: Brand.warn) }
                }
            }
            Text(tier.blurb).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            Meter(label: "Accuracy", value: Double(tier.accuracy) / Double(Tier.testCases), text: "\(tier.accuracy)/\(Tier.testCases)")
            Meter(label: "Speed", value: tier.speedScore, text: tier.speed)
            HStack {
                if selected {
                    Label("In use", systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Brand.good)
                } else if installed {
                    Button("Use \(tier.name)") { m.formatTier = tier.id }
                } else if let f = tier.file {
                    DownloadControl(file: f)
                }
                Spacer()
                if let f = tier.file, installed, !selected {
                    Button { m.deleteModel(tier) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete the downloaded \(tier.name) model (\(f.sizeLabel))")
                }
                Text("\(tier.ramLabel) while dictating")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .card(padding: 16, highlight: selected)
        .scaleEffect(hover && !selected && installed ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
        .onTapGesture { if installed { m.formatTier = tier.id } }
    }
}

struct Playground: View {
    @EnvironmentObject var m: AppModel
    @State private var input = "um so the meeting is on tuesday at 3 no wait thursday at 3 and we need to bring the slides the budget and uh the timeline"
    @State private var output = ""
    @State private var detail = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Test the formatter", symbol: "flask")
                Spacer()
                Text("Type it the way you'd say it").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            NoteEditor(text: $input, placeholder: "Type a messy sentence, like you'd speak it", minHeight: 70)
            HStack {
                Button { run() } label: {
                    HStack(spacing: 6) {
                        if running { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "sparkles") }
                        Text("Format")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(running || input.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("⌘↩").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                if !detail.isEmpty { Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            }
            if !output.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RESULT").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
                    Text(output).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.violet.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.violet.opacity(0.18)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
    }

    private func run() {
        running = true
        let text = input
        Task {
            let t0 = Date()
            let clean = TextCleaner.applyVocabulary(TextCleaner.basic(text))
            let gated = m.smartFormat && TextCleaner.needsSmartFormat(clean, raw: text)
            let out = gated ? TextCleaner.applyVocabulary(await TextCleaner.smartFormat(clean)) : clean
            if gated { await MainActor.run { TextCleaner.release() } }
            let ms = Date().timeIntervalSince(t0) * 1000
            let who = "\(m.currentTier.name) model"
            await MainActor.run {
                withAnimation(.snappy) { output = out }
                detail = gated ? "\(who) · \(ms < 1000 ? "\(Int(ms)) ms" : String(format: "%.2f s", ms / 1000))"
                               : (m.smartFormat ? "Plain sentence, model skipped" : "Smart formatting is off")
                running = false
            }
        }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @State private var confirmClear = false
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    var body: some View {
        Page {
            PageHeader(title: "Settings", subtitle: "Shortcut, behavior, permissions and privacy.")

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Dictation key", symbol: "keyboard")
                HStack(spacing: 12) {
                    ForEach(Hotkey.allCases, id: \.self) { HotkeyOption(hotkey: $0) }
                }
                Text("Hold to talk, release to paste. Tap once for hands-free, tap again to finish. Esc cancels.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.card()

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "Behavior", symbol: "slider.horizontal.3").padding(.bottom, 8)
                SettingToggle(title: "Smart formatting", detail: "Lists, self-corrections and filler cleanup. Choose the model in Models.", isOn: $m.smartFormat)
                Divider()
                SettingToggle(title: "Live preview", detail: "Show your words above the recording pill as you speak.", isOn: $m.livePreview)
                Divider()
                SettingToggle(title: "Sound effects", detail: "A soft click when recording starts and stops.", isOn: $m.sounds)
                Divider()
                SettingToggle(title: "Restore clipboard after pasting", detail: "LocalFlow pastes through the clipboard, then puts back what you had copied.", isOn: $m.restoreClipboard)
                Divider()
                SettingToggle(title: "Open at login", detail: "Start LocalFlow in the menu bar when you log in.",
                              isOn: Binding(get: { m.loginEnabled }, set: { m.setLogin($0) }))
            }.card()

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "Memory", symbol: "memorychip").padding(.bottom, 8)
                SettingRow(title: "Keep models loaded", detail: m.keepLoaded.detail) {
                    Picker("", selection: $m.keepLoaded) {
                        ForEach(KeepLoaded.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }.card()

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "Permissions", symbol: "hand.raised").padding(.bottom, 8)
                PermissionRow(symbol: "mic.fill", title: "Microphone", detail: "To hear you while the key is held.",
                              granted: m.micStatus == .authorized, action: m.requestMic)
                Divider()
                PermissionRow(symbol: "accessibility", title: "Accessibility", detail: "To notice the dictation key and paste into other apps.",
                              granted: m.axTrusted, action: m.requestAccessibility)
            }.card()

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "Privacy & data", symbol: "lock.shield").padding(.bottom, 8)
                SettingToggle(title: "Keep history", detail: "Save dictations on this Mac so you can find and copy them later.", isOn: $m.keepHistory)
                Divider()
                SettingRow(title: "Delete history", detail: "\(m.history.count) dictations stored.") {
                    Button("Delete…", role: .destructive) { confirmClear = true }.disabled(m.history.isEmpty)
                }
                Divider()
                SettingRow(title: "Data folder", detail: "History, stats, dictionary and logs.") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Config.vocabURL]) }
                }
                Divider()
                SettingRow(title: "Engine log", detail: !m.engineReady ? "Engine: \(m.status)" : m.engineLoaded ? "Speech engine is loaded." : "Speech engine is asleep. It starts when you dictate.") {
                    HStack {
                        Button("Open log") { NSWorkspace.shared.open(Config.logURL) }
                        Button("Unload models now") { m.restartEngine() }
                    }
                }
            }.card()
            .confirmationDialog("Delete all \(m.history.count) dictations?", isPresented: $confirmClear) {
                Button("Delete all", role: .destructive) { m.clearHistory() }
            } message: { Text("This can't be undone. Your stats are kept.") }

            HStack(spacing: 14) {
                AppGlyph(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LocalFlow \(version)").font(.system(size: 13.5, weight: .semibold))
                    Text("Speech by whisper.cpp. Formatting by LocalFlow's own English dictation models. Nothing leaves this Mac.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.card()
        }
        .onAppear { m.refreshPermissions() }
    }
}

struct HotkeyOption: View {
    @EnvironmentObject var m: AppModel
    let hotkey: Hotkey
    var compact = false
    @State private var hover = false
    var body: some View {
        let selected = m.hotkey == hotkey
        Button { m.hotkey = hotkey } label: {
            Group { if compact { compactLabel(selected) } else { fullLabel(selected) } }
            .padding(compact ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(selected ? Brand.violet.opacity(0.08) : Color.primary.opacity(hover ? 0.04 : 0.02)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private func radio(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16)).foregroundStyle(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.5)))
    }

    private func compactLabel(_ selected: Bool) -> some View {
        HStack(spacing: 14) {
            Keycap(label: hotkey.keycap, size: 22).frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(hotkey.name).font(.system(size: 13.5, weight: .semibold))
                Text(hotkey.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            radio(selected)
        }
    }

    private func fullLabel(_ selected: Bool) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Keycap(label: hotkey.keycap, size: 24)
                    Spacer()
                    radio(selected)
                }
                Text(hotkey.name).font(.system(size: 13.5, weight: .semibold))
                Text(hotkey.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
            }
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 11)
    }
}

struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        SettingRow(title: title, detail: detail) { Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Brand.violet) }
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(granted ? Brand.good : Brand.warn)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill((granted ? Brand.good : Brand.warn).opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Brand.good)
            } else {
                Button("Allow…", action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var m: AppModel
    @State var step = 0
    @State private var tryText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcome
                case 1: models
                case 2: permissions
                case 3: hotkey
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44).padding(.top, 40)
            .clipped()
            .layoutPriority(-1)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)

            HStack {
                if step > 0 { Button("Back") { withAnimation(.snappy) { step -= 1 } }.buttonStyle(.link) }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<5) { i in
                        Capsule().fill(i == step ? AnyShapeStyle(Brand.horizontal) : AnyShapeStyle(Color.primary.opacity(0.15)))
                            .frame(width: i == step ? 20 : 7, height: 7)
                    }
                }
                Spacer()
                Button(step == 4 ? "Start using LocalFlow" : step == 2 && !m.permissionsOK ? "Skip for now" : "Continue") {
                    if step == 4 { m.finishOnboarding() } else { withAnimation(.snappy) { step += 1 } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .background(Color.primary.opacity(0.03))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 580, height: 560)
        .background(Brand.pageBG)
        .onReceive(timer) { _ in m.refreshPermissions() }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            AppGlyph(size: 88)
            Text("Welcome to LocalFlow").font(.system(size: 28, weight: .bold))
            Text("Talk instead of type, in any app on your Mac.").font(.system(size: 15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Feature(symbol: "bolt.fill", title: "Fast", text: "Hold a key, talk, let go. Your words appear in under a second.")
                Feature(symbol: "lock.shield.fill", title: "Private", text: "Speech and formatting run on this Mac. No account, nothing uploaded.")
                Feature(symbol: "sparkles", title: "Understands you", text: "Say \"no wait, make that Thursday\" and it writes what you meant.")
            }
            .padding(.top, 10)
            Spacer()
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Getting the models").font(.system(size: 24, weight: .bold))
                Text("LocalFlow runs entirely on this Mac, so it downloads its models once. You can keep going while this finishes.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ModelRow(symbol: "waveform", title: "Speech recognition", detail: "Whisper Large v3 Turbo", file: .speech)
                if let f = m.recommended.file {
                    Divider()
                    ModelRow(symbol: "sparkles", title: "Smart formatting", detail: "\(m.recommended.name) model, the best fit for this Mac", file: f)
                }
            }.card(padding: 14)
            if let e = m.downloadError {
                Label("Download failed: \(e). Retry above, or later in Models.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Brand.warn).fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Models are saved in ~/Library/Application Support/LocalFlow and only load into memory while you dictate.",
                      systemImage: "memorychip")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Two quick permissions").font(.system(size: 24, weight: .bold))
                Text("macOS asks you to allow these once. LocalFlow only listens while you hold the key.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                PermissionRow(symbol: "mic.fill", title: "Microphone", detail: "So LocalFlow can hear you.",
                              granted: m.micStatus == .authorized, action: m.requestMic)
                Divider()
                PermissionRow(symbol: "accessibility", title: "Accessibility", detail: "So it can see the key and paste your words.",
                              granted: m.axTrusted, action: m.requestAccessibility)
            }.card(padding: 14)
            if !m.axTrusted {
                Label("In System Settings, switch on LocalFlow under Privacy & Security → Accessibility. This page updates by itself.",
                      systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if m.permissionsOK {
                Label("All set.", systemImage: "checkmark.seal.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.good)
            }
            Spacer()
        }
    }

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick your dictation key").font(.system(size: 24, weight: .bold))
                Text("You'll hold this key whenever you want to talk. You can change it later in Settings.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) { ForEach(Hotkey.allCases, id: \.self) { HotkeyOption(hotkey: $0, compact: true) } }
            Spacer()
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Give it a try").font(.system(size: 24, weight: .bold))
                HStack(spacing: 6) {
                    Text("Click the box, hold")
                    Keycap(label: m.hotkey.keycap, size: 18)
                    Text("and say something. Let go when you're done.")
                }.font(.system(size: 13.5)).foregroundStyle(.secondary)
            }
            if let p = m.progress(.speech) {
                Label("The speech model is still downloading (\(Int(p * 100))%). Dictation works as soon as it's done.", systemImage: "arrow.down.circle")
                    .font(.system(size: 12.5)).foregroundStyle(Brand.violet).fixedSize(horizontal: false, vertical: true)
            }
            NoteEditor(text: $tryText, placeholder: "Try: \"Remind me to call Sam at 3, actually make that 4.\"", minHeight: 130)
            if !tryText.isEmpty {
                Label("That's it. It works the same way in every app.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.good)
            }
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle").foregroundStyle(Brand.violet)
                Text("LocalFlow lives in your menu bar. Click the waveform icon any time for history, models and settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 11).fill(Brand.violet.opacity(0.07)))
            Spacer()
        }
    }
}

/// Onboarding row: a model with its download state.
struct ModelRow: View {
    @EnvironmentObject var m: AppModel
    let symbol: String, title: String, detail: String
    let file: ModelFile
    var body: some View {
        let _ = m.modelsVersion
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.violet).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text("\(detail) · \(file.sizeLabel)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if file.isInstalled {
                Label("Ready", systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Brand.good)
            } else {
                DownloadControl(file: file)
            }
        }
        .padding(.vertical, 9)
    }
}

struct Feature: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.gradient)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.violet.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }
}
