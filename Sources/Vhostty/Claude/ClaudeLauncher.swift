import Foundation

/// Builds the command that starts Claude Code inside a tab.
enum ClaudeLauncher {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// Writes the extra settings file passed via `claude --settings`. It only adds
    /// hooks (merged with the user's own settings); the user's config is untouched.
    /// This shared file identifies the tab through the environment; it is kept for
    /// sessions started before per-tab settings existed.
    static func writeSettings() {
        guard let exe = hookExecutable else { return }
        write(hookCommand: ShellQuote.quote(exe.path), to: AppPaths.claudeSettings)
        pruneTabSettings()
    }

    /// The settings file for one tab, with the tab baked into the hook command.
    /// When Claude Code sends a session to its background daemon (←), the worker
    /// keeps `--settings` but not the tab's environment, so this is what lets its
    /// hooks (and its new session id) still reach the tab.
    @discardableResult
    static func writeSettings(tabID: UUID) -> URL {
        let url = AppPaths.tabSettings.appendingPathComponent("\(tabID.uuidString).json")
        if let exe = hookExecutable {
            let command = [exe.path, "--tab", tabID.uuidString, "--sock", AppPaths.hookSocket]
                .map(ShellQuote.quote).joined(separator: " ")
            write(hookCommand: command, to: url)
        }
        return url
    }

    private static var hookExecutable: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("vhostty-hook")
    }

    private static func write(hookCommand: String, to url: URL) {
        let hook: [String: Any] = ["type": "command", "command": hookCommand, "timeout": 5]
        var hooks: [String: Any] = [:]
        for name in hookEvents {
            var entry: [String: Any] = ["hooks": [hook]]
            if name == "PostToolUse" { entry["matcher"] = "*" }
            hooks[name] = [entry]
        }
        let settings: [String: Any] = ["hooks": hooks]
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Per-tab files are rewritten on every launch; ones untouched for a month
    /// belong to long-closed tabs. (Not deleted on close: a background session
    /// may still be using the file.)
    private static func pruneTabSettings() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: AppPaths.tabSettings, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        for url in files {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date < cutoff { try? fm.removeItem(at: url) }
        }
    }

    static var launcherPath: String {
        (Bundle.main.resourcePath ?? "") + "/bin/vhostty-claude"
    }

    /// The shell command for a new tab: an interactive login shell (so the user's
    /// PATH and rc files apply) that runs Claude, then stays open as a normal shell.
    static func command(sessionID: String, resume: Bool) -> String {
        let shell = ShellQuote.quote(ShellEnvironment.shell)
        let flag = resume ? "--resume" : "--session-id"
        let inner = "\(ShellQuote.quote(launcherPath)) \(flag) \(sessionID); exec \(shell) -l"
        // libghostty already runs this as `exec -l <command>` under /bin/bash.
        return "\(shell) -l -i -c \(ShellQuote.quote(inner))"
    }

    static func environment(tabID: UUID) -> [String: String] {
        [
            "VHOSTTY_TAB_ID": tabID.uuidString,
            "VHOSTTY_SOCK": AppPaths.hookSocket,
            "VHOSTTY_CLAUDE_SETTINGS": writeSettings(tabID: tabID).path,
        ]
    }
}
