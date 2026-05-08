import Foundation
import Observation

/// Tracks which sessions are currently "in your court" — i.e. where the
/// next move is yours, not Claude's. This is a UX concept layered on top
/// of the raw `Session.status`.
///
/// Lifecycle:
///  - A session enters attention via `needsAttentionRaw`.
///  - The user "addresses" it by clicking a row in the HUD; we record
///    `dismissedAt[sessionId] = updatedAt` at that moment.
///  - If claude later does anything new, `updatedAt` bumps past the
///    dismissed mark and the session re-enters attention automatically.
///    This is the difference between "I've seen this" (transient) and
///    "I never want to see this" (which we never offer — that would
///    silently hide bugs).
@Observable
@MainActor
final class AttentionTracker {
    /// sessionId → the `updatedAt` value at the moment the user dismissed.
    /// We store the timestamp rather than a Bool so a fresh claude action
    /// (which bumps updatedAt) automatically invalidates the dismissal.
    private var dismissedAt: [String: Int] = [:]

    /// TODO(you): refine the predicate. The default below treats a session
    /// as "needs attention" when EITHER:
    ///   1. Claude is formally waiting for you (`status == .waiting`).
    ///   2. Claude is idle AND its last visible message was an assistant
    ///      message — i.e. claude said something and isn't working, so the
    ///      next move is yours.
    ///
    /// Variations you might want:
    ///   - Skip simulated/test sessions: `s.pid > 0`
    ///   - Time-gate option 2: only flag idle+assistant if `updatedAt`
    ///     is older than some threshold, to avoid flashing during a turn
    ///     transition where claude briefly looks idle.
    ///   - Treat busy sessions waiting on a long tool as "in your court"
    ///     after N minutes (claude probably stuck).
    func needsAttentionRaw(_ s: Session) -> Bool {
        if s.status == .waiting { return true }
        if s.status == .idle, s.lastMessage?.role == .assistant { return true }
        return false
    }

    /// Combines `needsAttentionRaw` with the user's dismissal state.
    /// If the session has no `updatedAt` at all, we conservatively treat
    /// it as still needing attention (rather than letting a single click
    /// silence it forever — claude has no way to "do something new" we
    /// can detect in that case).
    func needsAttention(_ s: Session) -> Bool {
        guard needsAttentionRaw(s) else { return false }
        guard let updatedAt = s.updatedAt else { return true }
        let dismissed = dismissedAt[s.sessionId] ?? -1
        return updatedAt > dismissed
    }

    /// Mark a session as "addressed". The dismissal expires automatically
    /// the next time `s.updatedAt` increases. Sessions without `updatedAt`
    /// can't be dismissed (see `needsAttention`).
    func dismiss(_ s: Session) {
        guard let updatedAt = s.updatedAt else { return }
        dismissedAt[s.sessionId] = updatedAt
    }

    /// Number of sessions currently in your court.
    func count(in sessions: [Session]) -> Int {
        sessions.lazy.filter { self.needsAttention($0) }.count
    }
}
