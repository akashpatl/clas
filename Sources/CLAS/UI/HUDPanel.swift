import AppKit

/// Borderless floating panel that hosts the HUD SwiftUI view.
///
/// Behavioural choices encoded here:
///  - `.nonactivatingPanel` so that focusing the HUD does NOT switch the
///    frontmost app away from Ghostty. Without this, every hotkey press
///    would steal focus from the terminal.
///  - `level = .statusBar` so we float above full-screen apps' content.
///  - `cancelOperation` (Esc) and `resignKey` (click-away) both dismiss.
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
