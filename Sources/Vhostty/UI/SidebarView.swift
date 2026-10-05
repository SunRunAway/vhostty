import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 40) // traffic lights
                .background(WindowDragArea())

            HStack(spacing: 6) {
                Text("Projects")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                IconButton(systemName: "plus", help: "Add Project (⇧⌘O)") { store.addProjectViaPanel() }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(store.projects) { project in
                        ProjectSection(store: store, project: project)
                    }
                    if store.projects.isEmpty {
                        Button { store.addProjectViaPanel() } label: {
                            Label("Add Your First Project…", systemImage: "folder.badge.plus")
                                .font(.system(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        // Solid, opaque background: a behind-window blur makes WindowServer
        // re-composite the blur every time the terminal draws a frame.
        .background(Color(red: 0.118, green: 0.118, blue: 0.125))
    }
}

private struct ProjectSection: View {
    @ObservedObject var store: AppStore
    let project: Project
    @State private var draggingID: UUID?

    private let historyLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProjectRow(store: store, project: project)
            if project.expanded {
                let query = store.searchQuery[project.id]
                let searching = !(query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let open = store.tabs(of: project).filter {
                    AppStore.matches(query ?? "", title: $0.title, sessionID: $0.sessionID)
                }
                let closed = store.closedHistory(for: project).filter {
                    AppStore.matches(query ?? "", title: $0.title, sessionID: $0.id)
                }
                let showAll = searching || store.showAllHistory.contains(project.id)

                if query != nil {
                    SessionSearchField(store: store, project: project)
                }

                ForEach(open) { tab in
                    SessionCard(tab: tab, store: store, draggingID: $draggingID)
                }
                .padding(.leading, 6)

                if !closed.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if !open.isEmpty {
                            Text("Past Sessions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 16)
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                        }
                        ForEach(closed.prefix(showAll ? closed.count : historyLimit)) { summary in
                            HistoryRow(store: store, project: project, summary: summary)
                        }
                        if closed.count > historyLimit {
                            Button {
                                if showAll { store.showAllHistory.remove(project.id) } else { store.showAllHistory.insert(project.id) }
                            } label: {
                                Text(showAll ? "Show Less" : "Show More" as LocalizedStringKey)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 16)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if searching && open.isEmpty && closed.isEmpty {
                    Text("No Matching Sessions")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 16)
                        .padding(.vertical, 5)
                } else if query == nil && open.isEmpty && closed.isEmpty {
                    Button { store.newSession(in: project) } label: {
                        Label("New Session", systemImage: "plus")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, project.expanded ? 10 : 0)
    }
}

private struct ProjectRow: View {
    @ObservedObject var store: AppStore
    let project: Project
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.expanded ? "folder" : "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(project.color)
                .frame(width: 18)
            Text(project.name)
                .font(.system(size: 13.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if hover {
                Menu {
                    projectMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                IconButton(systemName: "magnifyingglass", help: "Search Sessions") {
                    store.openSearch(project)
                }
                IconButton(systemName: "square.and.pencil", help: "New Claude Session") {
                    store.newSession(in: project)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.toggleExpanded(project) }
        .help(project.path.abbreviatingHome)
        .contextMenu { projectMenu }
    }

    @ViewBuilder
    private var projectMenu: some View {
        Button("New Claude Session") { store.newSession(in: project) }
        Button("Search Sessions") { store.openSearch(project) }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.path, forType: .string)
        }
        Divider()
        Button("Rename…") { store.renameProject(project) }
        Button("Change Directory…") { store.changeProjectDirectory(project) }
        Divider()
        Button("Remove Project…") { store.removeProject(project) }
    }
}

/// Filters a project's sessions by title or session id. Esc or ✕ closes it.
private struct SessionSearchField: View {
    @ObservedObject var store: AppStore
    let project: Project
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Title or Session ID", text: Binding(
                get: { store.searchQuery[project.id] ?? "" },
                set: { store.searchQuery[project.id] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($focused)
            .onExitCommand { store.closeSearch(project) }
            Button { store.closeSearch(project) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Search")
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
        .padding(.leading, 6)
        .onAppear { focused = true }
    }
}

private struct HistoryRow: View {
    @ObservedObject var store: AppStore
    let project: Project
    let summary: SessionSummary
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(summary.title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(RelativeTime.short(summary.modified))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .opacity(hover ? 1 : 0.8)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 27)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hover ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.resumeSession(summary, in: project) }
        .help("Resume session: \(summary.title)")
    }
}

struct IconButton: View {
    let systemName: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.10 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
        .help(help)
    }
}

enum RelativeTime {
    static func short(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        switch s {
        case ..<60: return String(localized: "now")
        case ..<3600: return String(localized: "\(Int(s / 60))m")
        case ..<86400: return String(localized: "\(Int(s / 3600))h")
        case ..<(86400 * 30): return String(localized: "\(Int(s / 86400))d")
        default:
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: date)
        }
    }
}
