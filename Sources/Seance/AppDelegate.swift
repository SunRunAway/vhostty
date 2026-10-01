import AppKit
import SwiftUI
import UserNotifications
import GhosttyC

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, GhosttyRuntimeDelegate,
    UNUserNotificationCenterDelegate {
    let store = AppStore.shared
    var window: NSWindow!
    private var hookServer: HookServer?
    private var debugSnapshot: DebugSnapshot?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .userInitiated).async { ShellEnvironment.load() }

        guard GhosttyRuntime.shared.start() else {
            let alert = NSAlert()
            alert.messageText = "终端引擎初始化失败"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        GhosttyRuntime.shared.delegate = self
        if let bg = GhosttyRuntime.shared.backgroundColor { store.terminalBackground = Color(nsColor: bg) }

        ClaudeLauncher.writeSettings()
        hookServer = HookServer(socketPath: AppPaths.hookSocket) { [weak self] event in
            self?.store.handleHook(event)
        }
        hookServer?.start()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        store.load()
        buildMenu()
        createWindow()
        store.activateSelection()

        if let dir = ProcessInfo.processInfo.environment["SEANCE_DEBUG_SNAPSHOT"] {
            debugSnapshot = DebugSnapshot(directory: dir, window: window, store: store)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Seance"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(store.terminalBackground)
        window.minSize = NSSize(width: 720, height: 420)
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(store: store))
        window.center()
        window.setFrameAutosaveName("SeanceMainWindow")
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let live = store.liveSessionCount
        if live > 0 {
            let alert = NSAlert()
            alert.messageText = "退出 Seance？"
            alert.informativeText = "有 \(live) 个终端仍在运行，退出会结束它们。标签页会被保存，下次打开时可以恢复 Claude 会话。"
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        store.save()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        unlink(AppPaths.hookSocket)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let tab = store.selectedTab, tab.attention {
            tab.attention = false
            store.updateDockBadge()
        }
        store.terminalContainer?.focusCurrent()
    }

    // MARK: - Menu

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Seance", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("打开 Ghostty 配置文件", #selector(openGhosttyConfig), ""))
        appMenu.addItem(item("重新加载配置", #selector(reloadConfig), "r", [.command, .shift]))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Seance", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Seance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(main, "Seance", appMenu)

        let file = NSMenu(title: "文件")
        file.addItem(item("新建 Claude 会话", #selector(newSession), "t"))
        file.addItem(item("添加项目…", #selector(addProject), "o", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("关闭会话", #selector(closeTab), "w"))
        addSubmenu(main, "文件", file)

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(main, "编辑", edit)

        let view = NSMenu(title: "显示")
        view.addItem(item("显示/隐藏侧栏", #selector(toggleSidebar), "s", [.command, .control]))
        view.addItem(item("显示/隐藏终端", #selector(toggleShell), "j"))
        view.addItem(item("聚焦 Claude", #selector(focusClaudePane), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option]))
        view.addItem(item("聚焦终端", #selector(focusShellPane), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option]))
        view.addItem(.separator())
        view.addItem(item("放大字体", #selector(fontBigger), "="))
        view.addItem(item("缩小字体", #selector(fontSmaller), "-"))
        view.addItem(item("实际大小", #selector(fontReset), "0"))
        view.addItem(.separator())
        view.addItem(item("进入全屏", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        addSubmenu(main, "显示", view)

        let win = NSMenu(title: "窗口")
        win.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(item("下一个会话", #selector(nextTab), "]", [.command, .shift]))
        win.addItem(item("上一个会话", #selector(previousTab), "[", [.command, .shift]))
        for i in 1...9 {
            let it = item("会话 \(i)", #selector(selectTabByTag(_:)), "\(i)")
            it.tag = i
            win.addItem(it)
        }
        win.addItem(.separator())
        win.addItem(item("主窗口", #selector(showMainWindow), ""))
        addSubmenu(main, "窗口", win)
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = self
        return it
    }

    private func addSubmenu(_ main: NSMenu, _ title: String, _ menu: NSMenu) {
        menu.title = title
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }

    @objc private func newSession() { store.newSession() }
    @objc private func addProject() { store.addProjectViaPanel() }
    @objc private func closeTab() { store.closeSelected() }
    @objc private func nextTab() { store.gotoTab(.next) }
    @objc private func previousTab() { store.gotoTab(.previous) }
    @objc private func selectTabByTag(_ sender: NSMenuItem) { store.selectTab(at: sender.tag - 1) }
    @objc private func showMainWindow() { window.makeKeyAndOrderFront(nil) }
    @objc private func reloadConfig() { GhosttyRuntime.shared.reloadConfig() }
    @objc private func openGhosttyConfig() {
        if let app = GhosttyRuntime.shared.app { ghostty_app_open_config(app) }
    }
    @objc private func toggleSidebar() {
        withAnimation(.easeOut(duration: 0.15)) { store.sidebarVisible.toggle() }
        store.scheduleSave()
    }
    @objc private func toggleShell() { store.toggleShell() }
    @objc private func focusClaudePane() { store.focusPane(shell: false) }
    @objc private func focusShellPane() { store.focusPane(shell: true) }
    @objc private func fontBigger() { store.selectedTab?.surface?.perform(action: "increase_font_size:1") }
    @objc private func fontSmaller() { store.selectedTab?.surface?.perform(action: "decrease_font_size:1") }
    @objc private func fontReset() { store.selectedTab?.surface?.perform(action: "reset_font_size") }

    // MARK: - GhosttyRuntimeDelegate

    func ghosttyNewTab(from surface: TerminalSurfaceView?) {
        if let surface, let tab = store.tab(for: surface), let p = store.project(tab.projectID) {
            store.newSession(in: p)
        } else {
            store.newSession()
        }
    }

    func ghosttyCloseTab(_ surface: TerminalSurfaceView) {
        if let tab = store.tab(for: surface) { store.requestClose(tab) }
    }

    func ghosttyGotoTab(_ target: GhosttyGotoTab) { store.gotoTab(target) }

    func ghosttyGotoSplit(_ direction: ghostty_action_goto_split_e) {
        switch direction {
        case GHOSTTY_GOTO_SPLIT_UP: store.focusPane(shell: false)
        case GHOSTTY_GOTO_SPLIT_DOWN: store.focusPane(shell: true)
        case GHOSTTY_GOTO_SPLIT_PREVIOUS, GHOSTTY_GOTO_SPLIT_NEXT: store.focusPane(shell: nil)
        default: break
        }
    }

    func ghosttySurfaceRequestedClose(_ surface: TerminalSurfaceView, processAlive: Bool) {
        store.surfaceRequestedClose(surface, processAlive: processAlive)
    }

    func ghosttyDesktopNotification(_ surface: TerminalSurfaceView?, title: String, body: String) {
        // Claude Code reports through hooks; plain OSC 9/777 notifications only
        // matter when the tab isn't in front.
        // Claude Code's own notification (it detects Ghostty via TERM_PROGRAM).
        // Like Ghostty, only show it when that session isn't what you're looking at.
        guard let surface, let tab = store.tab(for: surface) else { return }
        NSLog("Seance: desktop notification from tab %@: %@ / %@", tab.id.uuidString, title, body)
        if tab.id == store.selectedTabID && NSApp.isActive && window.isKeyWindow { return }
        tab.attention = true
        store.updateDockBadge()
        store.notify(tab, body: body.isEmpty ? title : body)
    }

    func ghosttyBell(_ surface: TerminalSurfaceView) {
        guard let tab = store.tab(for: surface), tab.id != store.selectedTabID || !NSApp.isActive else { return }
        tab.attention = true
        store.updateDockBadge()
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let idString = response.notification.request.content.userInfo["tab"] as? String
        DispatchQueue.main.async {
            if let idString, let id = UUID(uuidString: idString), let tab = self.store.tab(withID: id) {
                self.store.select(tab)
            }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
