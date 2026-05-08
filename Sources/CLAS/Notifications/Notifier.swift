import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "CLAS", category: "notifier")

/// Posts a Mac banner via `osascript display notification`.
///
/// We use osascript rather than `UNUserNotificationCenter` because:
///  - osascript works whether CLAS is running as a bundled .app or as
///    the bare SPM binary (UN crashes the latter — needs a bundle ID).
///  - Ad-hoc-signed apps frequently can't reliably get UN authorization
///    propagated; first-launch prompts may not appear at all, and once
///    macOS caches a "denied" state for the unsigned bundle ID it's
///    awkward to recover from.
///
/// Trade-off: the banner posts under Script Editor's identity. If the
/// user has explicitly disabled notifications for Script Editor, no
/// banner shows. Acceptable for now; will become moot when CLAS gets
/// proper Apple Developer ID signing + notarisation.
@MainActor
final class Notifier {
    private var lastFiredAt: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 1.5

    func notifyWaiting(_ session: Session) {
        if let last = lastFiredAt[session.sessionId],
           Date().timeIntervalSince(last) < dedupeWindow {
            return
        }
        lastFiredAt[session.sessionId] = Date()

        let soundClause = " sound name \"Glass\""
        let title = session.displayTitle.appleScriptEscaped
        let subtitle = session.cwd.appleScriptEscaped
        let body = (session.waitingFor ?? "Claude needs your attention").appleScriptEscaped
        let script = """
        display notification "\(body)" with title "\(title)" subtitle "\(subtitle)"\(soundClause)
        """
        Task.detached(priority: .userInitiated) {
            await Self.run(script)
        }
    }

    private nonisolated static func run(_ source: String) async {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            log.error("notifier: NSAppleScript init failed")
            return
        }
        script.executeAndReturnError(&error)
        if let error {
            log.error("notifier osascript error: \(String(describing: error), privacy: .public)")
        }
    }
}
