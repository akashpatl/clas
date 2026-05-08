import AppKit
import SwiftUI

/// Owns the HUD panel's lifecycle and toggle behaviour.
/// One panel is created lazily on first toggle and reused.
@MainActor
final class HUDController {
    private let store: SessionStore
    private let attention: AttentionTracker
    private var panel: HUDPanel?
    private let onSelectSession: (Session) -> Void

    init(
        store: SessionStore,
        attention: AttentionTracker,
        onSelectSession: @escaping (Session) -> Void
    ) {
        self.store = store
        self.attention = attention
        self.onSelectSession = onSelectSession
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> HUDPanel {
        let view = HUDView(store: store, attention: attention) { [weak self] session in
            self?.onSelectSession(session)
            self?.panel?.orderOut(nil)
        }
        let hosting = NSHostingView(rootView: view)
        // Let SwiftUI dictate the size; clamp to a reasonable starting frame.
        let initialSize = hosting.fittingSize == .zero
            ? NSSize(width: 640, height: 320)
            : hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: initialSize))
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: HUDPanel) {
        // Re-fit in case the session list grew/shrank between toggles.
        if let hosting = panel.contentView as? NSHostingView<HUDView> {
            let size = hosting.fittingSize
            if size != .zero {
                panel.setContentSize(size)
            }
        }
        guard let screen = NSScreen.main else { panel.center(); return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        // Sit ~25% from the top — Raycast-like sweet spot.
        let y = screenFrame.maxY - panelSize.height - screenFrame.height * 0.25
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
