import SwiftUI

struct RootView: View {
    @ObservedObject var store: AppStore
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            if store.sidebarVisible {
                SidebarView(store: store)
                    .frame(width: store.sidebarWidth)
                    .overlay(alignment: .trailing) { resizeHandle }
                Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1)
            }
            VStack(spacing: 0) {
                TitleStrip(store: store)
                ZStack {
                    store.terminalBackground
                    TerminalHost(store: store)
                    if store.tabs.isEmpty {
                        EmptyStateView(store: store)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? store.sidebarWidth
                        dragStartWidth = start
                        store.sidebarWidth = min(max(start + value.translation.width, 230), 520)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        store.scheduleSave()
                    })
    }
}

/// Slim draggable strip above the terminal showing what's selected.
struct TitleStrip: View {
    @ObservedObject var store: AppStore

    static let height: CGFloat = 34

    var body: some View {
        ZStack {
            WindowDragArea()
            if let tab = store.selectedTab {
                TitleStripLabel(tab: tab, project: store.project(tab.projectID))
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, store.sidebarVisible ? 0 : 76)
        .frame(height: Self.height)
        .background(store.terminalBackground)
    }
}

private struct TitleStripLabel: View {
    @ObservedObject var tab: TabSession
    let project: Project?

    var body: some View {
        HStack(spacing: 6) {
            if let project {
                Text(project.name).foregroundStyle(.tertiary)
                Text("/").foregroundStyle(.quaternary)
            }
            Text(tab.title).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 16)
    }
}

struct EmptyStateView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            Text("👻")
                .font(.system(size: 54))
            Text("Vhostty")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(store.projects.isEmpty
                 ? "Add a project directory, then summon Claude in it."
                 : "Choose a project to start a new \(store.defaultKind.name) session." as LocalizedStringKey)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if store.projects.isEmpty {
                    Button { store.addProjectViaPanel() } label: {
                        Label("Add Project…", systemImage: "folder.badge.plus").frame(minWidth: 180)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    ForEach(store.projects.prefix(6)) { p in
                        Button { store.newSession(in: p) } label: {
                            HStack {
                                Circle().fill(p.color).frame(width: 7, height: 7)
                                Text("New session in \(p.name)")
                            }
                            .frame(minWidth: 220)
                        }
                    }
                    Button("Add Project…") { store.addProjectViaPanel() }
                        .buttonStyle(.link)
                        .padding(.top, 4)
                }
            }
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                shortcut("⌘T", "New session in the current project")
                shortcut("⌘1…9", "Switch sessions")
                shortcut("⌘W", "Close session")
                shortcut("⌃⌘S", "Show/hide sidebar")
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.top, 12)
        }
        .padding(40)
    }

    private func shortcut(_ key: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(key).font(.system(size: 12, design: .monospaced)).frame(width: 56, alignment: .trailing)
            Text(text)
        }
    }
}
