import AppKit
import SwiftUI

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var expanded = true

    var color: Color { ProjectPalette.color(for: id) }
}

enum ProjectPalette {
    static let colors: [Color] = [
        Color(red: 0.55, green: 0.48, blue: 0.98), Color(red: 0.31, green: 0.72, blue: 0.96),
        Color(red: 0.98, green: 0.62, blue: 0.29), Color(red: 0.36, green: 0.82, blue: 0.55),
        Color(red: 0.95, green: 0.42, blue: 0.56), Color(red: 0.95, green: 0.80, blue: 0.30),
        Color(red: 0.42, green: 0.85, blue: 0.82), Color(red: 0.80, green: 0.55, blue: 0.95),
    ]

    static func color(for id: UUID) -> Color {
        // FNV-1a over the UUID bytes: stable across launches (unlike hashValue).
        var h: UInt64 = 0xcbf29ce484222325
        withUnsafeBytes(of: id.uuid) { for b in $0 { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
        return colors[Int(h % UInt64(colors.count))]
    }
}

enum SessionStatus: String, Codable {
    case dormant     // restored from disk, Claude not started yet
    case starting
    case working
    case idle
    case needsInput
    case exited
}

/// One horizontal tab = one terminal running one Claude Code session.
final class TabSession: ObservableObject, Identifiable {
    let id: UUID
    let projectID: UUID

    @Published var sessionID: String
    @Published var title: String
    @Published var branch: String?
    @Published var worktree: String?
    @Published var prNumber: Int?
    @Published var prURL: String?
    @Published var prState: String?
    @Published var status: SessionStatus
    @Published var attention = false

    var cwd: String
    var transcriptPath: String?
    var terminalTitle: String?
    var transcript: TranscriptInfo?
    var hooksActive = false
    var surface: TerminalSurfaceView?

    var isLaunched: Bool { surface != nil }

    init(id: UUID = UUID(), projectID: UUID, sessionID: String, cwd: String, title: String = "新会话",
         status: SessionStatus = .starting) {
        self.id = id
        self.projectID = projectID
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title
        self.status = status
    }

    var record: TabRecord {
        TabRecord(id: id, projectID: projectID, sessionID: sessionID, title: title, cwd: cwd,
                  branch: branch, worktree: worktree, prNumber: prNumber, prURL: prURL, prState: prState)
    }

    convenience init(record r: TabRecord) {
        self.init(id: r.id, projectID: r.projectID, sessionID: r.sessionID, cwd: r.cwd, title: r.title, status: .dormant)
        branch = r.branch
        worktree = r.worktree
        prNumber = r.prNumber
        prURL = r.prURL
        prState = r.prState
    }
}

struct TabRecord: Codable {
    var id: UUID
    var projectID: UUID
    var sessionID: String
    var title: String
    var cwd: String
    var branch: String?
    var worktree: String?
    var prNumber: Int?
    var prURL: String?
    var prState: String?
}

struct PersistedState: Codable {
    var projects: [Project] = []
    var tabs: [TabRecord] = []
    var selectedTabID: UUID?
    var sidebarWidth: Double?
    var sidebarVisible: Bool?
}
