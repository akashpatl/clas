import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "CLAS", category: "ghostty")

/// Bridges a `Session` to Ghostty's AppleScript surface.
///
/// Two-tier matcher:
///   1. **Named session** (Claude `/rename` was used): focus the first
///      terminal whose `name` contains the session name. Names are the
///      user's chosen unique handle and trump everything else.
///   2. **Unnamed session**: enumerate terminals whose `working directory`
///      equals `session.cwd`. Focus only when there's *exactly one*
///      candidate. If zero or many, just `activate` Ghostty (bring it to
///      front) without picking a specific terminal — focusing the wrong
///      tab is worse than focusing none.
///
/// Why we don't pick "first cwd match" anymore: a common setup is one
/// claude session + a bare zsh shell open in the same project directory.
/// Both match the cwd; "first" was randomly picking the bare shell, which
/// is exactly the bug a user reported.
///
/// Ghostty 1.3.0+ doesn't expose tty/pid on terminal (issue #11592), so
/// there's no way to disambiguate by walking the process tree from
/// outside. Until that lands, the rename-or-be-ambiguous trade-off stands.
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
            set targetTerminal to missing value
            set candidateCount to 0

            if wantedName is not "" then
                -- Named session: trust the name as a unique handle.
                repeat with w in windows
                    repeat with tb in tabs of w
                        repeat with term in terminals of tb
                            set tn to ""
                            try
                                set tn to name of term
                            end try
                            if tn contains wantedName then
                                set targetTerminal to term
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            else
                -- Unnamed session: only focus when cwd uniquely identifies.
                repeat with w in windows
                    repeat with tb in tabs of w
                        repeat with term in terminals of tb
                            set twd to ""
                            try
                                set twd to working directory of term
                            end try
                            if twd is wantedCwd then
                                set candidateCount to candidateCount + 1
                                if candidateCount is 1 then
                                    set targetTerminal to term
                                else
                                    -- More than one match — refuse to pick.
                                    set targetTerminal to missing value
                                end if
                            end if
                        end repeat
                    end repeat
                end repeat
            end if

            if targetTerminal is not missing value then
                focus targetTerminal
                return "ok"
            else
                -- No unambiguous match. Bring Ghostty to front so the user
                -- can pick the right tab themselves; better than guessing.
                activate
                if candidateCount > 1 then
                    return "ambiguous"
                else
                    return "no_match"
                end if
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
