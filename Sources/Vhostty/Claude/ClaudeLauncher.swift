import Foundation

/// Builds the command that starts Claude Code inside a tab.
enum ClaudeLauncher {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// Writes the extra settings file passed via `claude --settings`. It only adds
    /// hooks (merged with the user's own settings); the user's config is untouched.
    static func writeSettings() {
        guard let exe = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("vhostty-hook") else { return }
        let hook: [String: Any] = ["type": "command", "command": ShellQuote.quote(exe.path), "timeout": 5]
        var hooks: [String: Any] = [:]
        for name in hookEvents {
            var entry: [String: Any] = ["hooks": [hook]]
            if name == "PostToolUse" { entry["matcher"] = "*" }
            hooks[name] = [entry]
        }
        let settings: [String: Any] = ["hooks": hooks]
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: AppPaths.claudeSettings, options: .atomic)
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
            "VHOSTTY_CLAUDE_SETTINGS": AppPaths.claudeSettings.path,
        ]
    }
}
