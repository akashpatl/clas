import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "CLAS", category: "ghostty")

/// Bridges a `Session` to Ghostty's AppleScript surface.
///
/// Match strategy (priority order):
///   1. Terminal `name` contains `session.name` (Claude Code's `/rename`
///      sets the OSC title to "<status-icon> <name>"; substring matches it).
///   2. Terminal `working directory` equals `session.cwd` — used when the
///      session has no rename. Fragile when multiple Ghostty splits sit
///      in the same cwd; we pick the first hit.
///
/// On hit, `focus <terminal>` raises the window AND switches to the right
/// tab + pane in one call. No need to also call `activate window` / `select
/// tab` — Ghostty's `focus` command handles all three.
///
/// TODO(you): the matcher is the third learning-mode contribution point.
/// Consider:
///   - what to do when name *and* cwd both miss? (today: silently no-op;
///     could open a fresh Ghostty window via `new window`/`new tab`)
///   - what if multiple terminals match the cwd fallback? (today: first;
///     could prefer the most-recently-active by tracking via a dict)
@MainActor
final class GhosttyFocuser {
    func focus(_ session: Session) {
        // Don't auto-launch Ghostty on click if it isn't running.
        // The implicit-launch behaviour of `tell application "Ghostty"`
        // is surprising — clicking a row would pop open an empty window.
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.mitchellh.ghostty"
        }) else {
            log.info("focus skipped: Ghostty not running")
            return
        }
        let source = buildScript(for: session)
        log.info("focus pid=\(session.pid, privacy: .public) name=\(session.name ?? "(unnamed)", privacy: .private)")
        Task.detached(priority: .userInitiated) {
            await Self.run(source)
        }
    }

    private func buildScript(for session: Session) -> String {
        let nameQuery = session.name?.appleScriptEscaped ?? ""
        let cwdQuery = session.cwd.appleScriptEscaped
        return """
        tell application "Ghostty"
            set wantedName to "\(nameQuery)"
            set wantedCwd to "\(cwdQuery)"
            set found to missing value
            set fallback to missing value
            repeat with w in windows
                repeat with tb in tabs of w
                    repeat with term in terminals of tb
                        set tn to ""
                        try
                            set tn to name of term
                        end try
                        set twd to ""
                        try
                            set twd to working directory of term
                        end try
                        if (wantedName is not "") and (tn contains wantedName) then
                            set found to term
                            exit repeat
                        end if
                        if (fallback is missing value) and (twd is wantedCwd) then
                            set fallback to term
                        end if
                    end repeat
                    if found is not missing value then exit repeat
                end repeat
                if found is not missing value then exit repeat
            end repeat
            if found is missing value then set found to fallback
            if found is not missing value then
                focus found
                return "ok"
            else
                return "miss"
            end if
        end tell
        """
    }

    nonisolated static func run(_ source: String) async {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            log.error("NSAppleScript init failed")
            return
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            log.error("focus AppleScript error: \(String(describing: error), privacy: .public)")
        } else if let s = result.stringValue {
            log.info("focus result: \(s, privacy: .public)")
        }
    }
}
