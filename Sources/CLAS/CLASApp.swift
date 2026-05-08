import SwiftUI
import AppKit
import KeyboardShortcuts
import OSLog

private let log = Logger(subsystem: "CLAS", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    let attention = AttentionTracker()
    private var watcher: SessionsDirWatcher?
    private var hud: HUDController?
    private var hookListener: HookHTTPListener?
    private let focuser = GhosttyFocuser()
    private let notifier = Notifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil) // unbuffered prints when stdout is piped
        NSApp.setActivationPolicy(.accessory)

        // SessionStore → notifier wiring. Any session entering the formal
        // .waiting state still triggers a one-shot system banner; the
        // persistent menu-bar indicator is now driven by AttentionTracker
        // (broader predicate, sticky until you address each session).
        let notifier = self.notifier
        store.onEvent = { event in
            switch event {
            case .startedWaiting(let s), .waitingForChanged(let s, _):
                notifier.notifyWaiting(s)
            case .appeared, .disappeared, .stoppedWaiting:
                break
            }
        }

        let w = SessionsDirWatcher(store: store)
        w.start()
        watcher = w

        let listener = HookHTTPListener { [weak w] _ in
            w?.pingNow()
        }
        listener.start()
        hookListener = listener

        let attention = self.attention
        let controller = HUDController(store: store, attention: attention) { [weak self] session in
            self?.activate(session)
        }
        hud = controller

        KeyboardShortcuts.onKeyDown(for: .toggleHUD) { [weak controller] in
            log.info("hotkey fired")
            controller?.toggle()
        }

        let bound = KeyboardShortcuts.getShortcut(for: .toggleHUD)
        log.info("launched. hotkey bound: \(String(describing: bound), privacy: .public)")
    }

    /// Single entry point used by both the menu-bar popover and the HUD.
    /// Marks the session as addressed (drops it from the attention count)
    /// then raises the right Ghostty terminal. Ghostty becoming frontmost
    /// also auto-dismisses the popover, so we don't need to close it
    /// explicitly.
    ///
    /// On focus failure (ambiguous / no_match / Ghostty not running) we
    /// post a banner explaining why — silent activate-only previously
    /// looked like a CLAS bug to users.
    func activate(_ session: Session) {
        attention.dismiss(session)
        let notifier = self.notifier
        focuser.focus(session) { result in
            switch result {
            case .ambiguous, .noMatch, .ghosttyNotRunning:
                notifier.notifyFocusFailure(session, reason: result)
            case .ok, .error:
                break
            }
        }
    }
}

@main
struct CLASApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                store: appDelegate.store,
                attention: appDelegate.attention,
                onSelect: { session in appDelegate.activate(session) }
            )
        } label: {
            MenuBarLabel(
                store: appDelegate.store,
                attention: appDelegate.attention
            )
        }
        .menuBarExtraStyle(.window)
    }
}
