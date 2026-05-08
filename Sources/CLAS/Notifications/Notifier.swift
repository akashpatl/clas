import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "CLAS", category: "notifier")

/// Posts a Mac banner via `osascript display notification`.
///
/// Why not `UNUserNotificationCenter`: it requires the running process to
/// be a properly bundled, signed `.app` with a bundle identifier — SPM
/// `swift run` produces a bare executable, so UN crashes with
/// "Notifications cannot be scheduled without a bundle identifier".
/// `osascript` works regardless of bundling and is rich enough for v1.
///
/// Trade-off: clicking the banner does not deep-link back to CLAS
/// (it opens Script Editor or no-ops). For our flow that's fine — the user
/// hits the global hotkey to act, not the banner.
@MainActor
final class Notifier {
    /// Suppresses notifications fired within `dedupeWindow` of the previous
    /// one for the same session (the watcher and the hook can both detect
    /// the same transition within ~500ms).
    private var lastFiredAt: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 1.5

    func notifyWaiting(_ session: Session) {
        if let last = lastFiredAt[session.sessionId],
           Date().timeIntervalSince(last) < dedupeWindow {
            return
        }
        lastFiredAt[session.sessionId] = Date()

        let title = session.displayTitle
        let subtitle = session.cwd
        let body = session.waitingFor ?? "Claude needs your attention"
        post(title: title, subtitle: subtitle, body: body, sound: "Glass")
    }

    /// Banner explaining why a click on a session row didn't focus a tab.
    /// Different dedupe key than `notifyWaiting` so the two channels can't
    /// suppress each other.
    func notifyFocusFailure(_ session: Session, reason: GhosttyFocuser.FocusResult) {
        let key = "miss-\(session.sessionId)"
        if let last = lastFiredAt[key],
           Date().timeIntervalSince(last) < dedupeWindow {
            return
        }
        lastFiredAt[key] = Date()

        let body: String
        switch reason {
        case .ambiguous:
            body = "Multiple terminals at this directory. Use /rename in claude to make focus deterministic."
        case .noMatch:
            body = "No Ghostty tab found — the terminal might be in a closed window or another app."
        case .ghosttyNotRunning:
            body = "Ghostty isn't running."
        case .ok, .error:
            return // shouldn't be called for these, but defensive
        }
        post(title: "Couldn't focus \(session.displayTitle)",
             subtitle: session.cwd,
             body: body,
             sound: nil)
    }

    private func post(title: String, subtitle: String, body: String, sound: String?) {
        let script = """
        display notification "\(body.appleScriptEscaped)" with title "\(title.appleScriptEscaped)" subtitle "\(subtitle.appleScriptEscaped)"\(sound.map { " sound name \"\($0)\"" } ?? "")
        """
        Task.detached(priority: .userInitiated) {
            await Self.run(script)
        }
    }

    private nonisolated static func run(_ source: String) async {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return }
        script.executeAndReturnError(&error)
        if let error {
            log.error("notifier error: \(String(describing: error), privacy: .public)")
        }
    }
}
