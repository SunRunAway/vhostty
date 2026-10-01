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
                IconButton(systemName: "plus", help: "添加项目 (⇧⌘O)") { store.addProjectViaPanel() }
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
                            Label("添加第一个项目…", systemImage: "folder.badge.plus")
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
        .background(Color.black.opacity(0.22))
        .background(VisualEffect(material: .sidebar))
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
                let open = store.tabs(of: project)
                let closed = store.closedHistory(for: project)
                let showAll = store.showAllHistory.contains(project.id)

                ForEach(open) { tab in
                    SessionCard(tab: tab, store: store, draggingID: $draggingID)
                }
                .padding(.leading, 6)

                if !closed.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if !open.isEmpty {
                            Text("历史会话")
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
                                Text(showAll ? "收起" : "显示更多")
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
                if open.isEmpty && closed.isEmpty {
                    Button { store.newSession(in: project) } label: {
                        Label("新建会话", systemImage: "plus")
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
                IconButton(systemName: "square.and.pencil", help: "新建 Claude 会话") {
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
        Button("新建 Claude 会话") { store.newSession(in: project) }
        Divider()
        Button("在 Finder 中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
        }
        Button("拷贝路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.path, forType: .string)
        }
        Divider()
        Button("重命名…") { store.renameProject(project) }
        Button("更改目录…") { store.changeProjectDirectory(project) }
        Divider()
        Button("移除项目…") { store.removeProject(project) }
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
        .help("恢复会话：\(summary.title)")
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
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
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(s / 60))分钟"
        case ..<86400: return "\(Int(s / 3600))小时"
        case ..<(86400 * 30): return "\(Int(s / 86400))天"
        default:
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: date)
        }
    }
}
