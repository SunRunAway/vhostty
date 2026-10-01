import AppKit
import SwiftUI

/// Hosts whichever terminal surface belongs to the selected tab. Surfaces are kept
/// alive by their tabs and simply swapped in and out of this view.
final class TerminalContainerView: NSView {
    private(set) weak var current: TerminalSurfaceView?

    override var isOpaque: Bool { false }

    func show(_ surface: TerminalSurfaceView?) {
        if current === surface {
            focusCurrent()
            return
        }
        if let old = current {
            old.setVisible(false)
            old.removeFromSuperview()
        }
        current = surface
        guard let surface else { return }
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        surface.setVisible(true)
        focusCurrent()
    }

    func focusCurrent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let surface = self.current, let window = self.window else { return }
            if window.firstResponder !== surface { window.makeFirstResponder(surface) }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusCurrent()
    }
}

struct TerminalHost: NSViewRepresentable {
    @ObservedObject var store: AppStore

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        store.terminalContainer = view
        view.show(store.selectedTab?.surface)
        return view
    }

    func updateNSView(_ view: TerminalContainerView, context: Context) {
        if view.current !== store.selectedTab?.surface {
            view.show(store.selectedTab?.surface)
        }
    }
}

/// Empty bar space that drags the window (and zooms on double-click).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension View {
    /// Pointing-hand / resize cursors for SwiftUI elements.
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
