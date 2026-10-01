import SwiftUI
import UniformTypeIdentifiers

/// A session in the sidebar: a four-line card showing
/// title / branch / worktree / PR.
struct SessionCard: View {
    @ObservedObject var tab: TabSession
    @ObservedObject var store: AppStore
    @Binding var draggingID: UUID?
    @State private var hover = false

    private var selected: Bool { store.selectedTabID == tab.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                StatusIndicator(status: tab.status, attention: tab.attention)
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                closeButton
            }
            .frame(height: 18)

            infoLine("arrow.triangle.branch", tab.branch, placeholder: "无分支信息")
            infoLine("square.stack.3d.up", tab.worktree, placeholder: tab.branch == nil ? "—" : "主工作区",
                     tint: tab.worktree == nil ? .secondary : Color(red: 0.72, green: 0.55, blue: 1.0))
            prLine
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.white.opacity(0.11) : Color.white.opacity(hover ? 0.06 : 0.025)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.white.opacity(selected ? 0.16 : 0.05), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .opacity(draggingID == tab.id ? 0.45 : 1)
        .onHover { hover = $0 }
        .onTapGesture { store.select(tab) }
        .onDrag {
            draggingID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: CardDropDelegate(target: tab.id, store: store, draggingID: $draggingID))
        .help(tab.title)
        .contextMenu { contextMenu }
    }

    private var closeButton: some View {
        Button { store.requestClose(tab) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(hover ? 1 : 0)
        .help("关闭 (⌘W)")
    }

    private func infoLine(_ icon: String, _ text: String?, placeholder: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(text == nil ? Color.secondary.opacity(0.5) : tint)
                .frame(width: 13)
            Text(text ?? placeholder)
                .font(.system(size: 11.5, design: text == nil ? .default : .monospaced))
                .foregroundStyle(text == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(height: 15)
    }

    private var prLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tab.prNumber == nil ? Color.secondary.opacity(0.5) : prColor)
                .frame(width: 13)
            if let n = tab.prNumber {
                Text("#\(n)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(prColor)
                if let state = tab.prState, state != "OPEN" {
                    Text(state == "MERGED" ? "已合并" : "已关闭")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                if tab.prURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("无 PR")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 15)
        .contentShape(Rectangle())
        .onTapGesture {
            if let s = tab.prURL, let url = URL(string: s) { NSWorkspace.shared.open(url) } else { store.select(tab) }
        }
        .help(tab.prURL.map { "在浏览器中打开 \($0)" } ?? "")
    }

    private var prColor: Color {
        switch tab.prState {
        case "MERGED": return Color(red: 0.70, green: 0.52, blue: 1.0)
        case "CLOSED": return Color(red: 0.95, green: 0.42, blue: 0.42)
        default: return Color(red: 0.38, green: 0.82, blue: 0.48)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("关闭") { store.requestClose(tab) }
        Button("关闭其他会话") { store.closeOtherTabs(tab) }
        Divider()
        if let s = tab.prURL, let url = URL(string: s) {
            Button("在浏览器中打开 PR #\(tab.prNumber ?? 0)") { NSWorkspace.shared.open(url) }
        }
        Button("在 Finder 中显示目录") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tab.cwd)])
        }
        Button("拷贝会话 ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.sessionID, forType: .string)
        }
        Button("拷贝恢复命令") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("claude --resume \(tab.sessionID)", forType: .string)
        }
    }
}

struct StatusIndicator: View {
    let status: SessionStatus
    let attention: Bool

    var body: some View {
        Group {
            switch status {
            case .working:
                ProgressView().controlSize(.mini).scaleEffect(0.75)
            case .needsInput:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.25))
            case .idle:
                Circle()
                    .fill(attention ? Color(red: 0.35, green: 0.62, blue: 1.0) : Color(red: 0.38, green: 0.82, blue: 0.48))
                    .frame(width: 7, height: 7)
            case .starting:
                Circle().fill(Color.gray.opacity(0.7)).frame(width: 7, height: 7)
            case .dormant, .exited:
                Circle().strokeBorder(Color.gray.opacity(0.8), lineWidth: 1.2).frame(width: 7, height: 7)
            }
        }
        .frame(width: 12, height: 12)
        .help(statusHelp)
    }

    private var statusHelp: String {
        switch status {
        case .working: return "Claude 正在工作"
        case .needsInput: return "Claude 需要你确认"
        case .idle: return attention ? "Claude 已完成（未查看）" : "等待输入"
        case .starting: return "启动中"
        case .dormant: return "未启动（点击后恢复会话）"
        case .exited: return "Claude 已退出"
        }
    }
}

private struct CardDropDelegate: DropDelegate {
    let target: UUID
    let store: AppStore
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let id = draggingID, id != target else { return }
        withAnimation(.easeOut(duration: 0.12)) { store.moveTab(id, before: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
