import Foundation

// vhostty-hook: a Claude Code hook command that forwards the hook payload
// (JSON on stdin) to the Vhostty app over a Unix socket.
//
// It must never write to stdout (some hook outputs are fed back to Claude)
// and must always exit 0 quickly so it can't disturb the session.

// The tab comes from `--tab <uuid> --sock <path>` (baked into the per-tab
// settings file, so it survives Claude Code moving the session to its background
// daemon, whose worker doesn't inherit the tab's environment), else from the env.
// Without either (a worker started from the shared settings file) the event is
// still sent with an empty tab line; the app then finds the tab by session id.
func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let env = ProcessInfo.processInfo.environment

/// Same location as the app's AppPaths.hookSocket.
func defaultSocketPath() -> String {
    let support = env["VHOSTTY_SUPPORT_DIR"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Vhostty")
    let p = (support as NSString).appendingPathComponent("hook.sock")
    return p.utf8.count < 100 ? p : "/tmp/vhostty-\(getuid()).sock"
}

let tab = argument("--tab") ?? env["VHOSTTY_TAB_ID"] ?? ""
let sockPath = argument("--sock") ?? env["VHOSTTY_SOCK"] ?? defaultSocketPath()

var payload = Data((tab + "\n").utf8)
payload.append(FileHandle.standardInput.readDataToEndOfFile())

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var tv = timeval(tv_sec: 1, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(sockPath.utf8)
let fits = withUnsafeMutableBytes(of: &addr.sun_path) { buf -> Bool in
    guard pathBytes.count < buf.count else { return false }
    buf.copyBytes(from: pathBytes)
    buf[pathBytes.count] = 0
    return true
}
guard fits else { exit(0) }

let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { exit(0) }

payload.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return }
    var offset = 0
    while offset < raw.count {
        let n = write(fd, base + offset, raw.count - offset)
        if n <= 0 { break }
        offset += n
    }
}
close(fd)
exit(0)
