import AppKit
import SwiftUI

final class Localization: ObservableObject {
    static let shared = Localization()
    static let languages = [("pt", "Português"), ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano")]
    @Published var selection: String = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system" {
        didSet { UserDefaults.standard.set(selection, forKey: "interfaceLanguage") }
    }
    private let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: languages.compactMap { code, _ in
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (code, bundle)
    })
    var language: String {
        if Self.languages.contains(where: { $0.0 == selection }) { return selection }
        for preferred in Locale.preferredLanguages {
            let code = preferred.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? "en"
            if Self.languages.contains(where: { $0.0 == code }) { return code }
        }
        return "en"
    }
    func text(_ key: String) -> String {
        let fallback = bundles["en"]?.localizedString(forKey: key, value: key, table: nil) ?? key
        return bundles[language]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    }
}

struct Track {
    var title = ""
    var artist = ""
    var album = ""
    var source = ""
    var playing = false
    var position = 0.0
    var duration = 0.0
    var artwork: NSImage?
    var key: String { [source, title, artist, album].joined(separator: "\u{1F}") }
}

final class Player: ObservableObject {
    @Published var track = Track()
    @Published var problem: String?
    @Published var preference = "auto"
    private let worker = DispatchQueue(label: "music.bridge")
    private var busy = false
    private var timer: Timer?
    private var cachedKey = ""
    private var cachedArt: NSImage?
    private var lastArtworkAttempt = Date.distantPast
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    private func script(_ source: String) -> (NSAppleEventDescriptor?, String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: "with timeout of 3 seconds\n" + source + "\nend timeout")?.executeAndReturnError(&error)
        if let error {
            let denied = (error[NSAppleScript.errorNumber] as? Int) == -1743
            return (nil, denied ? "denied" : "connectionError")
        }
        return (result, nil)
    }
    func refresh() {
        guard !busy else { return }
        busy = true
        let preferred = preference
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        worker.async { [self] in
            var candidates: [Track] = []
            var failure: String?
            for (name, id) in [("Music", "com.apple.Music"), ("Spotify", "com.spotify.client")] {
                guard running.contains(id), preferred == "auto" || preferred == name else { continue }
                let duration = name == "Spotify" ? "(duration of t) / 1000" : "duration of t"
                let (result, error) = script("""
                tell application "\(name)"
                    if player state is stopped then return {}
                    set t to current track
                    return {name of t, artist of t, album of t, player state as text, player position, \(duration)}
                end tell
                """)
                failure = error ?? failure
                guard let r = result, r.numberOfItems >= 6 else { continue }
                var t = Track()
                t.title = r.atIndex(1)?.stringValue ?? ""
                t.artist = r.atIndex(2)?.stringValue ?? ""
                t.album = r.atIndex(3)?.stringValue ?? ""
                t.source = name
                t.playing = r.atIndex(4)?.stringValue == "playing"
                t.position = r.atIndex(5)?.doubleValue ?? 0
                t.duration = r.atIndex(6)?.doubleValue ?? 0
                candidates.append(t)
            }
            var selected = candidates.first(where: \.playing) ?? candidates.first ?? Track()
            // Keep the last successful cache through temporary metadata failures.
            // A new track must never inherit artwork from the previous track.
            if !selected.source.isEmpty && selected.key != cachedKey {
                cachedKey = selected.key
                cachedArt = nil
                lastArtworkAttempt = .distantPast
            }
            // Music may report a new track before its artwork becomes available.
            // Retry failed/missing artwork without re-downloading successful images.
            if !selected.source.isEmpty && cachedArt == nil && Date().timeIntervalSince(lastArtworkAttempt) >= 5 {
                lastArtworkAttempt = Date()
                if selected.source == "Music" {
                    let (art, _) = script("tell application \"Music\"\ntry\nreturn raw data of artwork 1 of current track\nend try\nend tell")
                    if let art { cachedArt = NSImage(data: art.data) }
                } else if selected.source == "Spotify" {
                    let (art, _) = script("tell application \"Spotify\" to return artwork url of current track")
                    if let raw = art?.stringValue, let url = URL(string: raw), url.scheme == "https" {
                        // A bounded request keeps the polling worker responsive when offline.
                        let semaphore = DispatchSemaphore(value: 0)
                        var downloaded: Data?
                        let task = URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 3)) { data, _, _ in
                            downloaded = data
                            semaphore.signal()
                        }
                        task.resume()
                        semaphore.wait()
                        if let downloaded { cachedArt = NSImage(data: downloaded) }
                    }
                }
            }
            selected.artwork = selected.key == cachedKey ? cachedArt : nil
            let finalTrack = selected
            let finalFailure = failure
            DispatchQueue.main.async {
                self.track = finalTrack
                self.problem = finalFailure
                self.busy = false
            }
        }
    }
    func command(_ command: String) {
        let source = track.source
        guard !source.isEmpty else { return }
        worker.async {
            let (_, error) = self.script("tell application \"\(source)\" to \(command)")
            DispatchQueue.main.async { self.problem = error; self.refresh() }
        }
    }
    func seek(_ fraction: Double) {
        command("set player position to \(max(0, min(track.duration, fraction * track.duration)))")
    }
    func openMusic() {
        let source = track.source.isEmpty ? preference : track.source
        let id = source == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }
}

struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Explicit AppKit drag surfaces avoid SwiftUI's hosting view swallowing window drags.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
            window?.saveFrame(usingName: "FloatingMusic")
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct Widget: View {
    @ObservedObject var player: Player
    @ObservedObject private var language = Localization.shared
    private func tr(_ key: String) -> String { language.text(key) }
    private var displayTitle: String { t.source.isEmpty ? tr("emptyTitle") : (t.title.isEmpty ? tr("untitled") : t.title) }
    @State private var hovering = false
    var close: () -> Void
    private var t: Track { player.track }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.09))
                if let art = t.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 32, weight: .light)).foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(WindowDragArea()).help(tr("dragCover"))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(t.playing ? Color.green : Color.white.opacity(0.35)).frame(width: 5, height: 5)
                    Button(action: { player.openMusic() }) {
                        Text(t.source.isEmpty ? "FLOATING MUSIC" : (t.source == "Music" ? "APPLE MUSIC" : "SPOTIFY"))
                            .font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1.1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.source == "Spotify" ? tr("openSpotify") : tr("openMusic"))
                    Spacer()
                    Menu {
                        Picker(tr("source"), selection: $player.preference) {
                            Text(tr("automatic")).tag("auto")
                            Text("Apple Music").tag("Music")
                            Text("Spotify").tag("Spotify")
                        }
                        Picker(tr("language"), selection: $language.selection) {
                            Text(tr("systemLanguage")).tag("system")
                            ForEach(Localization.languages, id: \.0) { code, name in
                                Text(name).tag(code)
                            }
                        }
                        Divider()
                        Button(tr("openApp")) { player.openMusic() }
                        Button(tr("quit")) { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis").frame(width: 20, height: 16) }
                    .menuStyle(.borderlessButton).fixedSize().help(tr("options"))
                }.foregroundStyle(.white.opacity(0.55))
                Text(displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(displayTitle).padding(.top, 5).overlay(WindowDragArea())
                Text(t.source.isEmpty ? tr("emptyArtist") : [t.artist, t.album].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).padding(.top, 2).overlay(WindowDragArea())
                if t.source.isEmpty {
                    Button(player.problem == nil ? tr("openMusic") + " ↗" : tr("allowAccess") + " ↗") {
                        if player.problem != nil, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                        else { player.openMusic() }
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).padding(.top, 12)
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 20) {
                        control("backward.fill", label: tr("previous"), size: 16) { player.command("previous track") }
                        control(t.playing ? "pause.fill" : "play.fill", label: t.playing ? tr("pause") : tr("play"), size: 20) { player.command("playpause") }
                        control("forward.fill", label: tr("next"), size: 16) { player.command("next track") }
                    }.frame(maxWidth: .infinity).padding(.vertical, 5)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(Color(red: 0.3, green: 0.66, blue: 1)).frame(width: geometry.size.width * min(1, max(0, t.position / max(1, t.duration))))
                        }.frame(height: 4).frame(height: 14).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onEnded { player.seek($0.location.x / max(1, geometry.size.width)) })
                    }.frame(height: 14).accessibilityLabel(tr("progress"))
                    HStack {
                        Text(time(t.position)); Spacer(); Text("−" + time(max(0, t.duration - t.position)))
                    }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16).frame(width: 360, height: 144)
        .background(WindowDragArea())
        .background(Glass())
        .background(Color(red: 0.12, green: 0.19, blue: 0.3).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.17), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.65)) }
                .buttonStyle(.plain).padding(6).opacity(hovering ? 1 : 0).help(tr("hide"))
        }
        .foregroundStyle(.white).onHover { hovering = $0 }
        .onChange(of: player.preference) { _ in player.refresh() }
        .help(player.problem.map { tr($0) } ?? tr("drag"))
    }
    func control(_ icon: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size, weight: .semibold)).frame(width: 30, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    func time(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private func tr(_ key: String) -> String { Localization.shared.text(key) }
    let player = Player()
    var panel: NSPanel!
    var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 144), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: Widget(player: player, close: { [weak self] in self?.panel.orderOut(nil) }))
        if !panel.setFrameUsingName("FloatingMusic") {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 390, y: screen.minY + 35))
        }
        panel.setContentSize(NSSize(width: 360, height: 144))
        panel.setFrameAutosaveName("FloatingMusic")
        panel.orderFrontRegardless()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Floating Music")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        rebuildMenu(menu)
        player.start()
    }
    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(menu) }
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: tr("toggle"), action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("quitApp"), action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
    }
    @objc func toggle() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
