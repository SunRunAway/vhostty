import Foundation

/// Builds the command that starts Claude Code (or Codex) inside a tab.
enum ClaudeLauncher {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// Writes the extra settings file passed via `claude --settings`. It only adds
    /// hooks (merged with the user's own settings); the user's config is untouched.
    static func writeSettings() {
        guard !hookPath.isEmpty else { return }
        let hook: [String: Any] = ["type": "command", "command": ShellQuote.quote(hookPath), "timeout": 5]
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

    static func launcherPath(_ kind: AgentKind) -> String {
        (Bundle.main.resourcePath ?? "") + "/bin/vhostty-\(kind.rawValue)"
    }

    /// The shell command for a new tab: an interactive login shell (so the user's
    /// PATH and rc files apply) that runs the agent, then stays open as a normal shell.
    /// Claude gets the session id up front. Codex can't, so its terminal title is set
    /// to its activity spinner, the thread title and the thread id (cut to its first
    /// 29 characters), and AppStore.terminalTitleChanged reads the id from there.
    static func command(kind: AgentKind, sessionID: String, resume: Bool) -> String {
        let shell = ShellQuote.quote(ShellEnvironment.shell)
        let args: String
        switch kind {
        case .claude: args = "\(resume ? "--resume" : "--session-id") \(sessionID)"
        case .codex:
            let title = "-c " + ShellQuote.quote(#"tui.terminal_title=["activity","thread-title","thread-id"]"#)
            args = resume ? "resume \(title) \(ShellQuote.quote(sessionID))" : title
        }
        let inner = "\(ShellQuote.quote(launcherPath(kind))) \(args); exec \(shell) -l"
        // libghostty already runs this as `exec -l <command>` under /bin/bash.
        return "\(shell) -l -i -c \(ShellQuote.quote(inner))"
    }

    static func environment(tabID: UUID) -> [String: String] {
        [
            "VHOSTTY_TAB_ID": tabID.uuidString,
            "VHOSTTY_SOCK": AppPaths.hookSocket,
            "VHOSTTY_CLAUDE_SETTINGS": AppPaths.claudeSettings.path,
            "VHOSTTY_HOOK": hookPath,
        ]
    }

    static var hookPath: String {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("vhostty-hook").path ?? ""
    }
}
