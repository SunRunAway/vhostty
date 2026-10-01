import AppKit
import Combine
import SwiftUI
import UserNotifications

/// All app state: projects, tabs, selection, and the glue to terminals and Claude.
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var projects: [Project] = []
    @Published var tabs: [TabSession] = []
    @Published private(set) var selectedTabID: UUID?
    @Published var history: [UUID: [SessionSummary]] = [:]
    @Published var showAllHistory: Set<UUID> = []
    @Published var sidebarVisible = true
    @Published var sidebarWidth: CGFloat = 300
    @Published var terminalBackground = Color(red: 0.16, green: 0.17, blue: 0.20)

    /// Set by the AppKit host so the store can move keyboard focus into terminals.
    weak var terminalContainer: TerminalContainerView?

    private var refreshTimer: Timer?
    private var historyTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private let infoQueue = DispatchQueue(label: "seance.info", qos: .utility)
    private var refreshing: Set<UUID> = []

    var selectedTab: TabSession? { tabs.first { $0.id == selectedTabID } }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func tabs(of project: Project) -> [TabSession] { tabs.filter { $0.projectID == project.id } }

    /// The project new sessions go to by default.
    var currentProject: Project? {
        if let tab = selectedTab, let p = project(tab.projectID) { return p }
        return projects.first
    }

    // MARK: - Lifecycle

    func load() {
        if let data = try? Data(contentsOf: AppPaths.state),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            projects = state.projects
            tabs = state.tabs.filter { r in state.projects.contains { $0.id == r.projectID } }.map(TabSession.init(record:))
            selectedTabID = state.selectedTabID ?? tabs.first?.id
            if let w = state.sidebarWidth { sidebarWidth = CGFloat(w) }
            if let v = state.sidebarVisible { sidebarVisible = v }
        }
        if selectedTabID != nil, selectedTab == nil { selectedTabID = tabs.first?.id }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refreshAllInfo()
        }
        historyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshHistory()
        }
        refreshHistory()
        refreshAllInfo()
    }

    /// Called once the window exists: start Claude in the selected tab.
    func activateSelection() {
        if let tab = selectedTab { select(tab) }
    }

    func save() {
        let state = PersistedState(
            projects: projects,
            tabs: tabs.map(\.record),
            selectedTabID: selectedTabID,
            sidebarWidth: Double(sidebarWidth),
            sidebarVisible: sidebarVisible)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: AppPaths.state, options: .atomic)
        }
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Projects

    func addProjectViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加项目"
        panel.message = "选择一个项目目录，Claude 会话将在这里启动"
        guard panel.runModal() == .OK else { return }
        var last: Project?
        for url in panel.urls {
            if let existing = projects.first(where: { $0.path == url.path }) {
                last = existing
                continue
            }
            let p = Project(name: url.lastPathComponent, path: url.path)
            projects.append(p)
            last = p
        }
        scheduleSave()
        refreshHistory()
        if let last, tabs(of: last).isEmpty { newSession(in: last) }
    }

    func renameProject(_ project: Project) {
        let alert = NSAlert()
        alert.messageText = "重命名项目"
        alert.informativeText = project.path.abbreviatingHome
        let field = NSTextField(string: project.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let name = field.stringValue.nonEmpty else { return }
        updateProject(project.id) { $0.name = name }
    }

    func changeProjectDirectory(_ project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: project.path)
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateProject(project.id) { $0.path = url.path }
        refreshHistory()
    }

    func removeProject(_ project: Project) {
        let open = tabs(of: project)
        let alert = NSAlert()
        alert.messageText = "移除项目「\(project.name)」？"
        alert.informativeText = open.isEmpty
            ? "只会从 Seance 中移除，不会删除任何文件。"
            : "它的 \(open.count) 个标签页会被关闭（会话记录仍保留，可以之后恢复）。不会删除任何文件。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for tab in open { closeTab(tab, force: true) }
        projects.removeAll { $0.id == project.id }
        history.removeValue(forKey: project.id)
        scheduleSave()
    }

    func toggleExpanded(_ project: Project) {
        updateProject(project.id) { $0.expanded.toggle() }
    }

    func moveProject(from source: IndexSet, to destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    private func updateProject(_ id: UUID, _ body: (inout Project) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        body(&projects[i])
        scheduleSave()
    }

    // MARK: - Tabs

    func newSession(in project: Project? = nil) {
        guard let project = project ?? currentProject else {
            addProjectViaPanel()
            return
        }
        let tab = TabSession(projectID: project.id, sessionID: UUID().uuidString.lowercased(), cwd: project.path)
        insertAfterSelection(tab)
        select(tab)
    }

    func resumeSession(_ summary: SessionSummary, in project: Project) {
        if let open = tabs.first(where: { $0.sessionID == summary.id }) {
            select(open)
            return
        }
        let tab = TabSession(projectID: project.id, sessionID: summary.id, cwd: project.path, title: summary.title)
        insertAfterSelection(tab)
        select(tab)
    }

    private func insertAfterSelection(_ tab: TabSession) {
        if let sel = selectedTab, let i = tabs.firstIndex(where: { $0 === sel }) {
            // Keep a project's tabs together: insert after the last tab of the same project.
            if let lastSame = tabs.lastIndex(where: { $0.projectID == tab.projectID }), lastSame >= i {
                tabs.insert(tab, at: lastSame + 1)
            } else {
                tabs.insert(tab, at: i + 1)
            }
        } else {
            tabs.append(tab)
        }
        scheduleSave()
    }

    func select(_ tab: TabSession) {
        launchIfNeeded(tab)
        tab.attention = false
        if selectedTabID != tab.id { selectedTabID = tab.id }
        terminalContainer?.show(tab.surface)
        updateDockBadge()
        scheduleSave()
    }

    /// Tabs in sidebar order (grouped by project, projects in sidebar order).
    var orderedTabs: [TabSession] {
        projects.flatMap { p in tabs.filter { $0.projectID == p.id } }
    }

    func selectTab(at index: Int) {
        let ordered = orderedTabs
        guard ordered.indices.contains(index) else { return }
        let tab = ordered[index]
        if let p = project(tab.projectID), !p.expanded { toggleExpanded(p) }
        select(tab)
    }

    func gotoTab(_ target: GhosttyGotoTab) {
        let ordered = orderedTabs
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedTabID } ?? 0
        switch target {
        case .previous: selectTab(at: (current - 1 + ordered.count) % ordered.count)
        case .next: selectTab(at: (current + 1) % ordered.count)
        case .last: selectTab(at: ordered.count - 1)
        case .index(let i): selectTab(at: min(max(i - 1, 0), ordered.count - 1))
        }
    }

    func moveTab(_ id: UUID, before target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        scheduleSave()
    }

    /// Closing via UI: ask the terminal to close (it confirms if Claude is still running).
    func requestClose(_ tab: TabSession) {
        if let surface = tab.surface, !surface.processExited {
            surface.requestClose()
        } else {
            closeTab(tab, force: true)
        }
    }

    func closeSelected() {
        if let tab = selectedTab { requestClose(tab) }
    }

    func closeOtherTabs(_ keep: TabSession) {
        let others = tabs.filter { $0 !== keep && $0.isLaunched && !($0.surface?.processExited ?? true) }
        if !others.isEmpty {
            let alert = NSAlert()
            alert.messageText = "关闭其他 \(others.count) 个正在运行的会话？"
            alert.informativeText = "会话记录会保留，之后可以从侧栏恢复。"
            alert.addButton(withTitle: "关闭")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        for tab in tabs where tab !== keep { closeTab(tab, force: true) }
    }

    func closeTab(_ tab: TabSession, force: Bool) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedTabID
        let ordered = orderedTabs
        let orderedIndex = ordered.firstIndex { $0 === tab } ?? 0
        if terminalContainer?.current === tab.surface { terminalContainer?.show(nil) }
        tab.surface = nil
        tabs.remove(at: index)
        if wasSelected {
            // Prefer the neighbour in the same project, then the next card in the sidebar.
            let remaining = ordered.filter { $0 !== tab }
            if remaining.isEmpty {
                selectedTabID = nil
            } else {
                let sameProject = remaining.filter { $0.projectID == tab.projectID }
                let next = sameProject.isEmpty
                    ? remaining[min(orderedIndex, remaining.count - 1)]
                    : (remaining.first { r in ordered.firstIndex { $0 === r }! > orderedIndex && r.projectID == tab.projectID }
                        ?? sameProject.last!)
                select(next)
            }
        }
        updateDockBadge()
        refreshHistory()
        scheduleSave()
    }

    func tab(for surface: TerminalSurfaceView) -> TabSession? {
        tabs.first { $0.surface === surface }
    }

    func tab(withID id: UUID) -> TabSession? { tabs.first { $0.id == id } }

    /// libghostty asks to close a surface (cmd+w, or the shell exited).
    func surfaceRequestedClose(_ surface: TerminalSurfaceView, processAlive: Bool) {
        guard let tab = tab(for: surface) else { return }
        if processAlive {
            let alert = NSAlert()
            alert.messageText = "关闭「\(tab.title)」？"
            alert.informativeText = "Claude 仍在运行，关闭会结束它。会话记录会保留，可以之后从侧栏恢复。"
            alert.addButton(withTitle: "关闭")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        closeTab(tab, force: true)
    }

    // MARK: - Launching Claude

    private func launchIfNeeded(_ tab: TabSession) {
        guard tab.surface == nil, let project = project(tab.projectID) else { return }
        let transcript = Transcript.locate(sessionID: tab.sessionID, projectPath: project.path)
        let workdir = FileManager.default.fileExists(atPath: project.path) ? project.path : NSHomeDirectory()
        let options = TerminalSurfaceView.Options(
            workingDirectory: workdir,
            command: ClaudeLauncher.command(sessionID: tab.sessionID, resume: transcript != nil),
            environment: ClaudeLauncher.environment(tabID: tab.id))
        let surface = TerminalSurfaceView(options: options)
        surface.onTitleChange = { [weak self, weak tab] title in
            guard let self, let tab else { return }
            self.terminalTitleChanged(tab, title)
        }
        tab.surface = surface
        tab.transcriptPath = transcript?.path
        tab.status = .starting
        tab.hooksActive = false
        refreshInfo(tab)
    }

    // MARK: - Titles & status

    /// Claude Code prefixes its terminal title with a status glyph: a braille
    /// spinner while working, "✳" when idle.
    private func terminalTitleChanged(_ tab: TabSession, _ raw: String) {
        var title = raw.trimmingCharacters(in: .whitespaces)
        var glyph: Character?
        if let first = title.first, !first.isLetter, !first.isNumber,
           title.count > 2, title[title.index(after: title.startIndex)] == " " {
            glyph = first
            title = String(title.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        // "✳" means idle / waiting for you; any other glyph (◐◓◑◒, braille dots, ✶✻…)
        // is Claude's working spinner.
        if let g = glyph {
            let idle = g == "✳"
            if !idle, tab.status != .needsInput {
                tab.status = .working
            } else if idle, !tab.hooksActive, tab.status == .working || tab.status == .starting {
                tab.status = .idle
            }
        }

        let generic = ["claude", "claude code", ""].contains(title.lowercased())
            || title.hasPrefix("/") || title.hasPrefix("~") || title.contains("@")
        tab.terminalTitle = generic ? nil : title
        updateTitle(tab)
    }

    private func updateTitle(_ tab: TabSession) {
        let t = tab.transcript
        let title = t?.customTitle ?? tab.terminalTitle ?? t?.aiTitle ?? t?.summary ?? t?.firstPrompt
        if let title, title != tab.title {
            tab.title = title
            scheduleSave()
        }
    }

    func handleHook(_ event: HookEvent) {
        guard let tab = tab(withID: event.tabID) else { return }
        tab.hooksActive = true
        if let sid = event.sessionID, sid != tab.sessionID {
            tab.sessionID = sid
            scheduleSave()
        }
        if let path = event.transcriptPath { tab.transcriptPath = path }
        if let cwd = event.cwd { tab.cwd = cwd }

        let isBackground = tab.id != selectedTabID || !NSApp.isActive
        switch event.name {
        case "SessionStart":
            if tab.status != .working { tab.status = .idle }
        case "UserPromptSubmit", "PostToolUse":
            tab.status = .working
        // System notifications come from Claude Code itself (OSC 9/777 through
        // Ghostty, honoring the user's Claude notification settings). Hooks only
        // drive the status icon and the unread marker.
        case "Notification":
            tab.status = .needsInput
            if isBackground { tab.attention = true }
        case "Stop":
            tab.status = .idle
            if isBackground { tab.attention = true }
            refreshHistory()
        case "SessionEnd":
            tab.status = .exited
        default:
            break
        }
        updateDockBadge()
        refreshInfo(tab)
    }

    // MARK: - Branch / worktree / PR

    private func refreshAllInfo() {
        for tab in tabs { refreshInfo(tab) }
    }

    func refreshInfo(_ tab: TabSession) {
        guard !refreshing.contains(tab.id), let project = project(tab.projectID) else { return }
        refreshing.insert(tab.id)
        let sessionID = tab.sessionID
        let knownPath = tab.transcriptPath
        let hookCwd = tab.hooksActive || !tab.isLaunched ? tab.cwd : nil

        infoQueue.async { [weak self] in
            let url = knownPath.map { URL(fileURLWithPath: $0) }
                ?? Transcript.locate(sessionID: sessionID, projectPath: project.path)
            let info = url.flatMap { Transcript.read($0) }
            let cwd = hookCwd ?? info?.cwd ?? project.path
            let git = GitProbe.probe(cwd) ?? (cwd != project.path ? GitProbe.probe(project.path) : nil)
            let pr = git.flatMap { GitProbe.pullRequest(toplevel: $0.toplevel, branch: $0.branch) }

            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing.remove(tab.id)
                guard self.tabs.contains(where: { $0 === tab }) else { return }
                if let url { tab.transcriptPath = url.path }
                tab.transcript = info
                self.updateTitle(tab)

                if let git {
                    if tab.branch != git.branch { tab.branch = git.branch }
                } else if let b = info?.gitBranch, b != "HEAD", tab.branch == nil {
                    tab.branch = b
                }

                var worktree: String?
                if let git, let linked = git.linkedWorktree {
                    if case .some(.some(let wt)) = info?.worktree, git.toplevel.hasPrefix(wt.path) || wt.path.hasPrefix(git.toplevel) {
                        worktree = wt.name
                    } else {
                        worktree = linked
                    }
                } else if git == nil, case .some(.some(let wt)) = info?.worktree {
                    worktree = wt.name
                }
                if tab.worktree != worktree { tab.worktree = worktree }

                if let pr {
                    tab.prNumber = pr.number
                    tab.prURL = pr.url
                    tab.prState = pr.state
                } else if let n = info?.prNumber {
                    tab.prNumber = n
                    tab.prURL = info?.prURL
                    tab.prState = nil
                } else if git != nil {
                    tab.prNumber = nil
                    tab.prURL = nil
                    tab.prState = nil
                }
            }
        }
    }

    func refreshHistory() {
        let snapshot = projects
        infoQueue.async { [weak self] in
            var result: [UUID: [SessionSummary]] = [:]
            for p in snapshot { result[p.id] = Transcript.history(projectPath: p.path) }
            DispatchQueue.main.async { self?.history = result }
        }
    }

    /// History sessions that aren't currently open in a tab.
    func closedHistory(for project: Project) -> [SessionSummary] {
        let open = Set(tabs.map(\.sessionID))
        return (history[project.id] ?? []).filter { !open.contains($0.id) }
    }

    // MARK: - Attention

    func updateDockBadge() {
        let n = tabs.filter(\.attention).count
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    func notify(_ tab: TabSession, body: String) {
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = tab.title
        if let p = project(tab.projectID) { content.subtitle = p.name }
        content.body = body
        content.userInfo = ["tab": tab.id.uuidString]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("Seance: notification failed: %@", error.localizedDescription) }
        }
    }

    var liveSessionCount: Int {
        tabs.filter { $0.surface.map { !$0.processExited } ?? false }.count
    }
}
