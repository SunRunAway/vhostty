import AppKit
import UserNotifications

/// Development aid: with SEANCE_DEBUG_SNAPSHOT=<dir>, periodically writes a PNG of
/// the window and a text dump of the app state and visible terminal text, so the
/// UI can be checked without screen-recording permission.
final class DebugSnapshot {
    private let directory: URL
    private weak var window: NSWindow?
    private let store: AppStore
    private var timer: Timer?

    init(directory: String, window: NSWindow, store: AppStore) {
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        self.window = window
        self.store = store
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.capture() }
    }

    /// Commands from <dir>/input.txt (consumed on read), one per line. Input only
    /// ever goes to a tab named explicitly with `to <tab uuid>`, never to "whatever
    /// is selected", so a test can't type into a real session by accident.
    ///   to <uuid> / toshell <uuid> · text <s> · enter · down · up · esc ·
    ///   select <uuid> · new · notify · toggleshell · focus claude|shell
    private func drive() {
        let url = directory.appendingPathComponent("input.txt")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        var target: TabSession?
        var targetShell = false
        for line in content.split(separator: "\n").map(String.init) {
            if line.hasPrefix("to ") {
                target = UUID(uuidString: String(line.dropFirst(3))).flatMap { store.tab(withID: $0) }
                targetShell = false
                continue
            }
            if line.hasPrefix("toshell ") {
                target = UUID(uuidString: String(line.dropFirst(8))).flatMap { store.tab(withID: $0) }
                targetShell = true
                continue
            }
            if line.hasPrefix("menukey ") {
                // menukey <ctrl|cmd> <char>: route a shortcut through the main menu.
                let parts = line.split(separator: " ").map(String.init)
                if parts.count == 3, let window = window {
                    let mods: NSEvent.ModifierFlags = parts[1] == "ctrl" ? [.control] : [.command]
                    if let ev = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: parts[2],
                        charactersIgnoringModifiers: parts[2], isARepeat: false, keyCode: parts[2] == "`" ? 0x32 : 0x26) {
                        _ = NSApp.mainMenu?.performKeyEquivalent(with: ev)
                    }
                }
                continue
            }
            if line == "cmdj-through-terminal", let window = window, let surface = store.selectedTab?.surface {
                // Mirror AppKit's key-equivalent routing: the window's view tree
                // first (our terminal), then the main menu.
                window.makeFirstResponder(surface)
                if let ev = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: "j",
                    charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 0x26) {
                    let byView = window.performKeyEquivalent(with: ev)
                    let byMenu = byView ? false : (NSApp.mainMenu?.performKeyEquivalent(with: ev) ?? false)
                    try? "terminalConsumed=\(byView) menuHandled=\(byMenu)".write(
                        to: directory.appendingPathComponent("keyequiv.txt"), atomically: true, encoding: .utf8)
                }
                continue
            }
            if line == "toggleshell" {
                store.toggleShell()
                continue
            }
            if line.hasPrefix("focus ") {
                store.focusPane(shell: line.hasSuffix("shell"))
                continue
            }
            if line.hasPrefix("select "), let id = UUID(uuidString: String(line.dropFirst(7))), let tab = store.tab(withID: id) {
                store.select(tab)
                continue
            }
            if line == "new" {
                store.newSession()
                continue
            }
            guard let tab = target, let surface = targetShell ? tab.shellSurface : tab.surface else { continue }
            switch line {
            case "enter": surface.debugPress(keyCode: 0x24, chars: "\r")
            case "down": surface.debugPress(keyCode: 0x7D, chars: "\u{F701}")
            case "up": surface.debugPress(keyCode: 0x7E, chars: "\u{F700}")
            case "esc": surface.debugPress(keyCode: 0x35, chars: "\u{1b}")
            case "notify":
                store.notify(tab, body: "Seance 测试通知")
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    let text = "authorization=\(settings.authorizationStatus.rawValue)"
                    try? text.write(to: self.directory.appendingPathComponent("notify.txt"), atomically: true, encoding: .utf8)
                }
            default:
                if line.hasPrefix("text ") { surface.sendText(String(line.dropFirst(5))) }
            }
        }
    }

    private func capture() {
        drive()
        guard let window, let view = window.contentView else { return }

        // Window server image (includes the Metal terminal layer).
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            write(NSBitmapImageRep(cgImage: cg), "window.png")
        }
        // AppKit rendering (SwiftUI chrome only, no terminal pixels).
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            write(rep, "chrome.png")
        }

        var lines: [String] = []
        lines.append("projects: " + store.projects.map { "\($0.name)=\($0.path)" }.joined(separator: ", "))
        lines.append("selected: \(store.selectedTabID?.uuidString ?? "-")")
        lines.append("firstResponder: \(String(describing: window.firstResponder.map { type(of: $0) }))")
        for tab in store.tabs {
            lines.append("--- tab \(tab.id) status=\(tab.status) attention=\(tab.attention) hooks=\(tab.hooksActive)")
            lines.append("    title=\(tab.title) | terminalTitle=\(tab.terminalTitle ?? "-")")
            lines.append("    session=\(tab.sessionID) cwd=\(tab.cwd)")
            lines.append("    branch=\(tab.branch ?? "-") worktree=\(tab.worktree ?? "-") pr=\(tab.prNumber.map(String.init) ?? "-") \(tab.prState ?? "")")
            if let sh = tab.shellSurface {
                lines.append("    shell: visible=\(tab.shellVisible) focused=\(tab.shellFocused) cwd=\(tab.shellCwd ?? "-") frame=\(sh.frame) inWindow=\(sh.window != nil)")
                lines.append(sh.visibleText().split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { "    s| " + $0 }.joined(separator: "\n"))
            }
            if let s = tab.surface {
                lines.append("    frame=\(s.frame) inWindow=\(s.window != nil)")
                lines.append(s.visibleText().split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "    | " + $0 }.joined(separator: "\n"))
            }
        }
        for (pid, items) in store.history {
            let name = store.project(pid)?.name ?? "?"
            lines.append("history[\(name)]: " + items.prefix(5).map(\.title).joined(separator: " / "))
        }
        try? lines.joined(separator: "\n").write(to: directory.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
    }

    private func write(_ rep: NSBitmapImageRep, _ name: String) {
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent(name))
        }
    }
}
