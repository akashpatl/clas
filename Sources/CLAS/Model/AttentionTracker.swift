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
    /// Stores claude's epoch-millis (Int), NOT a wall-clock Date — compared
    /// directly against `Session.updatedAt`. Storing the timestamp rather
    /// than a Bool means a fresh claude action (which bumps updatedAt)
    /// automatically invalidates the dismissal.
    private var dismissedAt: [String: Int] = [:]

    /// sessionId → wall-clock `Date` of the last time the user activated
    /// this session via the HUD or popover (pressed ↩ or clicked a row).
    /// Drives MRU sort: the row you just pressed floats to the top next
    /// time you open the HUD. Independent of claude's `updatedAt`.
    /// Aged on write: entries older than `activationTTL` get pruned so
    /// the map doesn't grow unbounded across long-running app lifetimes.
    private var activatedAt: [String: Date] = [:]
    private let activationTTL: TimeInterval = 7 * 24 * 60 * 60 // 7 days

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

    /// Record that the user has just activated (pressed ↩ / clicked) this
    /// session in the HUD or popover. Powers the MRU sort.
    /// Opportunistically prunes any entry older than `activationTTL` so
    /// the map stays bounded over a long-running app lifetime.
    func recordActivation(_ s: Session) {
        let cutoff = Date().addingTimeInterval(-activationTTL)
        activatedAt = activatedAt.filter { $0.value > cutoff }
        activatedAt[s.sessionId] = Date()
    }

    /// Wall-clock time of the last user activation, or `.distantPast`
    /// for sessions the user has never activated through CLAS. Returning
    /// `.distantPast` instead of `nil` keeps the sort comparator trivial.
    func lastActivation(of sessionId: String) -> Date {
        activatedAt[sessionId] ?? .distantPast
    }
}
