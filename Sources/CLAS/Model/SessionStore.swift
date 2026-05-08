import Foundation
import Observation

/// What changed between two snapshots of the sessions directory.
/// `SessionStore.diff` produces these; the app reacts to each one
/// (e.g. `.startedWaiting` triggers a notification + sound).
enum SessionEvent: Equatable {
    case appeared(Session)
    case disappeared(pid: Int)
    case startedWaiting(Session)
    case stoppedWaiting(Session)
    case waitingForChanged(Session, oldText: String?)
}

/// Single source of truth for the live session list.
/// `apply(snapshot:)` is called by `SessionsDirWatcher` whenever the
/// directory changes; it diffs against the previous state and emits events.
@Observable
@MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []

    /// Stream of events for downstream consumers (notifier, etc).
    var onEvent: ((SessionEvent) -> Void)?

    var waitingCount: Int {
        sessions.lazy.filter { $0.status == .waiting }.count
    }

    func apply(snapshot newSessions: [Session]) {
        let events = Self.diff(old: sessions, new: newSessions)
        sessions = newSessions
        for event in events { onEvent?(event) }
    }

    /// TODO(you): notification policy. Today's behaviour:
    ///   - any session newly entering `.waiting` fires `.startedWaiting`
    ///   - new/removed sessions fire appeared/disappeared
    ///   - a session that's already waiting and whose `waitingFor` text
    ///     changes is silently ignored (no re-ping)
    ///
    /// Things you might want to change:
    ///   - re-ping if `waitingFor` text changes (the question is different)
    ///   - re-ping if a session has been waiting > N minutes (nudge)
    ///   - suppress pings when the focused app is already that Ghostty tab
    ///     (you're looking at it; don't be annoying)
    ///
    /// Keep this pure: input → events. Side-effects live in callers.
    ///
    /// Keyed by `sessionId`, not `pid`: pid can be reused by a new claude
    /// process when an old one exits (especially in rapid kill+restart
    /// cycles). Keying by sessionId means a new sessionId on the same pid
    /// correctly fires `.appeared` instead of being misread as a status
    /// change on the old session.
    static func diff(old: [Session], new: [Session]) -> [SessionEvent] {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.sessionId, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.sessionId, $0) })
        var events: [SessionEvent] = []

        for (sid, session) in newByID {
            if let prev = oldByID[sid] {
                if prev.status != .waiting && session.status == .waiting {
                    events.append(.startedWaiting(session))
                } else if prev.status == .waiting && session.status != .waiting {
                    events.append(.stoppedWaiting(session))
                } else if session.status == .waiting && prev.waitingFor != session.waitingFor {
                    events.append(.waitingForChanged(session, oldText: prev.waitingFor))
                }
            } else {
                events.append(.appeared(session))
                if session.status == .waiting {
                    events.append(.startedWaiting(session))
                }
            }
        }
        for (sid, oldSession) in oldByID where newByID[sid] == nil {
            events.append(.disappeared(pid: oldSession.pid))
        }
        return events
    }
}
