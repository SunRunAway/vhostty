import Darwin
import Foundation

/// The Claude Code sessions running in each tab, found without hooks: Claude
/// Code keeps ~/.claude/sessions/<pid>.json for every running process, and a
/// `claude` typed into the tab's shell (after the first one exits) inherits the
/// tab's VHOSTTY_TAB_ID.
enum LiveSessions {
    struct Entry {
        let pid: pid_t
        let sessionID: String
        let cwd: String?
        let startedAt: Double
    }

    static let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")

    private static let lock = NSLock()
    /// Tab id from each process's environment, keyed by pid and start time (pids get reused).
    private static var tabOfProcess: [String: UUID?] = [:]

    /// The interactive session running in each tab. With several (a `claude`
    /// started by Claude itself), the one started first is the tab's own.
    static func scan() -> [UUID: Entry] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [:] }
        var result: [UUID: Entry] = [:]
        var live: Set<String> = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = (obj["pid"] as? NSNumber)?.int32Value,
                  let sessionID = (obj["sessionId"] as? String)?.nonEmpty,
                  (obj["kind"] as? String ?? "interactive") == "interactive",
                  let started = processStart(pid) else { continue }
            let key = "\(pid)@\(started)"
            live.insert(key)
            guard let tab = tab(of: pid, key: key) else { continue }
            let entry = Entry(pid: pid, sessionID: sessionID, cwd: obj["cwd"] as? String,
                              startedAt: (obj["startedAt"] as? NSNumber)?.doubleValue ?? started)
            if let other = result[tab], other.startedAt <= entry.startedAt { continue }
            result[tab] = entry
        }
        lock.lock()
        tabOfProcess = tabOfProcess.filter { live.contains($0.key) }
        lock.unlock()
        return result
    }

    private static func tab(of pid: pid_t, key: String) -> UUID? {
        lock.lock()
        if let cached = tabOfProcess[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        // An unreadable environment (not ours yet, or gone) is retried next time.
        guard let env = environment(pid) else { return nil }
        let tab = env["VHOSTTY_TAB_ID"].flatMap(UUID.init(uuidString:))
        lock.lock()
        tabOfProcess[key] = tab
        lock.unlock()
        return tab
    }

    /// Start time of a live process (seconds since 1970), nil if it's gone.
    private static func processStart(_ pid: pid_t) -> Double? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let tv = info.kp_proc.p_starttime
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
    }

    /// A process's environment, from KERN_PROCARGS2: argc, the executable path,
    /// argv, then the environment, all NUL-separated.
    private static func environment(_ pid: pid_t) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        let argc = buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        let strings = buf[MemoryLayout<Int32>.size..<size]
            .split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        // strings[0] is the executable path, then argc arguments.
        guard strings.count > Int(argc) else { return nil }
        var env: [String: String] = [:]
        for s in strings.dropFirst(Int(argc) + 1) {
            guard let eq = s.firstIndex(of: "=") else { continue }
            env[String(s[..<eq])] = String(s[s.index(after: eq)...])
        }
        return env
    }
}
