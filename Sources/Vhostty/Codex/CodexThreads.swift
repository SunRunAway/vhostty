import Foundation
import SQLite3

/// Codex sessions ("threads"), read from the index Codex keeps in
/// ~/.codex/state_<n>.sqlite.
enum CodexThreads {
    struct Thread {
        let id: String
        let cwd: String
        let title: String?
        let firstPrompt: String?
        let branch: String?
        let modified: Date
        let rolloutPath: String
    }

    /// Where Codex keeps its data: CODEX_HOME as the tabs' shells see it.
    static var home: URL {
        if let dir = ShellEnvironment.codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]?.nonEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    /// The newest state database (the number goes up with Codex's schema).
    static func database() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let best = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let n = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (n, name)
        }.max { $0.0 < $1.0 }
        return best.map { home.appendingPathComponent($0.1) }
    }

    /// Sessions a person started (not subagents, reviews or automations).
    private static let interactive = """
        archived = 0 AND source IN ('cli', 'vscode') AND ifnull(nullif(thread_source, ''), 'user') = 'user'
        """
    private static let columns = """
        id, cwd, name, title, git_branch, updated_at, rollout_path
        """

    static func thread(id: String) -> Thread? {
        guard !id.isEmpty else { return nil }
        return query("SELECT \(columns) FROM threads WHERE id = ?", [id]).first
    }

    /// Recent sessions started in a project or any worktree of its repository, newest first.
    static func history(projectPath: String, limit: Int = 40) -> [SessionSummary] {
        let dirs = directories(projectPath)
        let marks = dirs.map { _ in "?" }.joined(separator: ",")
        let rows = query("""
            SELECT \(columns) FROM threads
            WHERE \(interactive) AND preview <> '' AND cwd IN (\(marks))
            ORDER BY updated_at DESC LIMIT ?
            """, dirs + [min(limit, Int(Int32.max))])
        return rows.compactMap { t in
            guard let title = t.title ?? t.firstPrompt else { return nil }
            return SessionSummary(id: t.id, title: title, modified: t.modified,
                                  path: URL(fileURLWithPath: t.rolloutPath), kind: .codex)
        }
    }

    private static func directories(_ projectPath: String) -> [String] {
        var dirs = [projectPath]
        for path in [realpath(projectPath)] + GitProbe.worktrees(projectPath) where !dirs.contains(path) {
            dirs.append(path)
        }
        return dirs
    }

    private static func realpath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: - SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func query(_ sql: String, _ binds: [Any]) -> [Thread] {
        guard let url = database() else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Vhostty: Codex state query failed: %@", String(cString: sqlite3_errmsg(db)))
            return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in binds.enumerated() {
            if let n = value as? Int {
                sqlite3_bind_int64(stmt, Int32(i + 1), sqlite3_int64(n))
            } else {
                sqlite3_bind_text(stmt, Int32(i + 1), "\(value)", -1, transient)
            }
        }
        var rows: [Thread] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ col: Int32) -> String? {
                sqlite3_column_text(stmt, col).map { String(cString: $0) }
            }
            guard let id = text(0) else { continue }
            rows.append(Thread(
                id: id,
                cwd: text(1) ?? "",
                title: text(2)?.nonEmpty,
                firstPrompt: text(3).flatMap(oneLine),
                branch: text(4)?.nonEmpty,
                modified: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5))),
                rolloutPath: text(6) ?? ""))
        }
        return rows
    }

    private static func oneLine(_ s: String) -> String? {
        let line = s.split(whereSeparator: \.isNewline).lazy.compactMap { String($0).nonEmpty }.first
        return line.map { String($0.prefix(120)) }
    }
}
